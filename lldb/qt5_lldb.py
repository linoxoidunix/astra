# Форматтеры Qt5 для LLDB (codelldb). Подключение:
#   command script import /path/to/qt5_lldb.py
#
# Поля читаются ПО ИМЕНАМ из отладочной информации (d->size, d->offset, left/right),
# а не по захардкоженным смещениям: раскладка QArrayData/QMapNode различается между
# сборками Qt, а имена полей стабильны.
import lldb


def _ptr_size(valobj):
    return valobj.GetTarget().GetAddressByteSize()


def _find_type(target, name):
    """Ищет тип по имени, перебирая варианты записи вложенных шаблонов: GCC пишет
    в DWARF `QMapNode<QString, QPair<int, QString> >` — с пробелом перед каждым
    закрывающим угловым. Без этого узлы map/hash со сложным значением не находятся
    и контейнер молча показывается пустым."""
    seen, cands = set(), []
    cur = name
    while cur not in seen:
        seen.add(cur)
        cands.append(cur)
        cur = cur.replace(">>", "> >")
    for c in cands:
        t = target.FindFirstType(c)
        if t.IsValid():
            return t
    for c in cands:
        lst = target.FindTypes(c)
        if lst.GetSize() > 0:
            return lst.GetTypeAtIndex(0)
    return lldb.SBType()


def _raw(valobj):
    """Сырое значение без синтетических детей. Нужно всем провайдерам: у контейнера,
    вложенного в другой контейнер, valobj приходит уже синтетическим — там нет поля
    d, и контейнер молча оказывается пустым (QMap внутри QList)."""
    return valobj.GetNonSyntheticValue() if valobj.IsValid() else valobj


def _read(valobj, addr, size):
    if size <= 0:
        return b""
    err = lldb.SBError()
    data = valobj.GetProcess().ReadMemory(addr, size, err)
    return b"" if err.Fail() else data


# ---------------------------------------------------------------- QString / QByteArray
def _array_data(valobj):
    """QArrayData-подобный d: возвращает (адрес первого элемента, число элементов)."""
    d = _raw(valobj).GetChildMemberWithName("d")
    if not d.IsValid() or d.GetValueAsUnsigned(0) == 0:
        return 0, 0
    size = d.GetChildMemberWithName("size").GetValueAsSigned(0)
    offset = d.GetChildMemberWithName("offset").GetValueAsSigned(0)
    return d.GetValueAsUnsigned(0) + offset, size


def qstring_summary(valobj, internal_dict):
    addr, size = _array_data(valobj)
    if addr == 0:
        return "(null)"
    if size <= 0:
        return '""'
    raw = _read(valobj, addr, size * 2)
    return '"%s"' % raw.decode("utf-16-le", "replace")


def qbytearray_summary(valobj, internal_dict):
    addr, size = _array_data(valobj)
    if addr == 0:
        return "(null)"
    if size <= 0:
        return '""'
    raw = _read(valobj, addr, size)
    return '"%s"' % raw.decode("utf-8", "replace")


# ---------------------------------------------------------------- QVector / QList
class QVectorProvider:
    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.addr, self.count = _array_data(self.valobj)
        self.elem = self.valobj.GetType().GetUnqualifiedType().GetTemplateArgumentType(0)
        self.elem_size = self.elem.GetByteSize() if self.elem.IsValid() else 0
        if self.elem_size == 0:
            self.count = 0
        return False

    def num_children(self):
        return self.count

    def get_child_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def get_child_at_index(self, i):
        if i < 0 or i >= self.count:
            return None
        return self.valobj.CreateValueFromAddress(
            "[%d]" % i, self.addr + i * self.elem_size, self.elem
        )


# Типы, объявленные в Qt как Q_MOVABLE_TYPE/Q_PRIMITIVE_TYPE (в том числе через
# Q_DECLARE_SHARED). Только они лежат в слоте QList напрямую; всё остальное —
# по указателю. В DWARF QTypeInfo нет, определить иначе нельзя, поэтому список.
_MOVABLE = {
    "QString", "QByteArray", "QChar", "QLatin1String", "QStringRef", "QBitArray",
    "QDate", "QTime", "QDateTime", "QUrl", "QVariant", "QUuid", "QLocale",
    "QRegExp", "QRegularExpression", "QPersistentModelIndex", "QModelIndex",
    "QPoint", "QPointF", "QSize", "QSizeF", "QRect", "QRectF", "QLine", "QLineF",
    "QMargins", "QColor", "QPixmap", "QImage", "QBrush", "QPen", "QFont", "QIcon",
    "QKeySequence",
}


def _stored_inline(elem, ptr_size):
    """Правило QList (qlist.h): по указателю, если QTypeInfo<T>::isLarge || isStatic.
    isStatic по умолчанию ИСТИНА для классов, не объявленных movable, — поэтому
    неизвестный класс считаем лежащим по указателю (так хранятся QMap, QHash, QList)."""
    if not elem.IsValid():
        return False
    if elem.GetByteSize() > ptr_size:          # isLarge
        return False
    canon = elem.GetCanonicalType()
    if canon.GetTypeClass() in (
        lldb.eTypeClassPointer, lldb.eTypeClassEnumeration, lldb.eTypeClassBuiltin
    ):
        return True
    return elem.GetUnqualifiedType().GetName() in _MOVABLE


class QListProvider:
    """Qt5 QList: d->array[begin..end). Movable-типы лежат в самом слоте,
    остальные — по указателю из слота (см. _stored_inline)."""

    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.count = 0
        # QStringList наследует QList<QString>: d и параметр шаблона лежат в базовом
        # подобъекте, у самого QStringList их нет — спускаемся в базу.
        obj = _raw(self.valobj)
        d = obj.GetChildMemberWithName("d")
        if not d.IsValid() and obj.GetNumChildren() > 0:
            obj = obj.GetChildAtIndex(0)
            d = obj.GetChildMemberWithName("d")
        if not d.IsValid() or d.GetValueAsUnsigned(0) == 0:
            return False
        begin = d.GetChildMemberWithName("begin").GetValueAsSigned(0)
        end = d.GetChildMemberWithName("end").GetValueAsSigned(0)
        array = d.GetChildMemberWithName("array")
        if not array.IsValid():
            return False
        self.ptr_size = _ptr_size(self.valobj)
        self.base = array.GetLoadAddress() + begin * self.ptr_size
        self.count = max(0, end - begin)
        self.elem = obj.GetType().GetUnqualifiedType().GetTemplateArgumentType(0)
        self.inline = _stored_inline(self.elem, self.ptr_size)
        return False

    def num_children(self):
        return self.count

    def get_child_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def get_child_at_index(self, i):
        if i < 0 or i >= self.count or not self.elem.IsValid():
            return None
        slot = self.base + i * self.ptr_size
        if self.inline:
            return self.valobj.CreateValueFromAddress("[%d]" % i, slot, self.elem)
        raw = _read(self.valobj, slot, self.ptr_size)
        if len(raw) < self.ptr_size:
            return None
        addr = int.from_bytes(raw, "little")
        return self.valobj.CreateValueFromAddress("[%d]" % i, addr, self.elem)


def qcontainer_summary(valobj, internal_dict):
    n = valobj.GetNumChildren()
    return "size=%d" % n


def _pair_child(valobj, node_addr, node_t, i):
    """Ребёнок ассоциативного контейнера: имя — ключ, значение — value.
    Внутренние поля узла (left/right/p, next/h) в панель не пускаем."""
    node = valobj.CreateValueFromAddress("node", node_addr, node_t)
    key = node.GetChildMemberWithName("key")
    val = node.GetChildMemberWithName("value")
    if not val.IsValid():
        return node
    label = key.GetSummary() or key.GetValue()
    name = "[%s]" % label if label else "[%d]" % i
    return valobj.CreateValueFromAddress(name, val.GetLoadAddress(), val.GetType())


# ---------------------------------------------------------------- QMap
class QMapProvider:
    """Qt5 QMap — красно-чёрное дерево. Корень: d->header.left. Обходим по порядку
    рекурсивно (left, self, right) — так не нужны родительские указатели с цветом
    в младших битах."""

    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.nodes = []
        d = _raw(self.valobj).GetChildMemberWithName("d")
        if not d.IsValid() or d.GetValueAsUnsigned(0) == 0:
            return False
        t = self.valobj.GetType().GetUnqualifiedType()
        key_t = t.GetTemplateArgumentType(0)
        val_t = t.GetTemplateArgumentType(1)
        if not (key_t.IsValid() and val_t.IsValid()):
            return False
        node_t = _find_type(
            self.valobj.GetTarget(), "QMapNode<%s, %s>" % (key_t.GetName(), val_t.GetName())
        )
        if not node_t.IsValid():
            return False
        self.node_t = node_t
        root = d.GetChildMemberWithName("header").GetChildMemberWithName("left")
        self._walk(root.GetValueAsUnsigned(0), 0)
        return False

    def _walk(self, addr, depth):
        # depth защищает от зацикливания на повреждённом дереве
        if addr == 0 or depth > 64 or len(self.nodes) > 10000:
            return
        node = self.valobj.CreateValueFromAddress("node", addr, self.node_t)
        left = node.GetChildMemberWithName("left").GetValueAsUnsigned(0)
        right = node.GetChildMemberWithName("right").GetValueAsUnsigned(0)
        self._walk(left, depth + 1)
        self.nodes.append(addr)
        self._walk(right, depth + 1)

    def num_children(self):
        return len(self.nodes)

    def get_child_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def get_child_at_index(self, i):
        if i < 0 or i >= len(self.nodes):
            return None
        return _pair_child(self.valobj, self.nodes[i], self.node_t, i)


# ---------------------------------------------------------------- QHash
class QHashProvider:
    """Qt5 QHash: массив buckets[numBuckets], в каждом — цепочка next.
    Конец цепочки — сам d (QHashData используется как сигнальный узел)."""

    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.nodes = []
        d = _raw(self.valobj).GetChildMemberWithName("d")
        if not d.IsValid():
            return False
        d_addr = d.GetValueAsUnsigned(0)
        if d_addr == 0:
            return False
        size = d.GetChildMemberWithName("size").GetValueAsSigned(0)
        num_buckets = d.GetChildMemberWithName("numBuckets").GetValueAsSigned(0)
        buckets = d.GetChildMemberWithName("buckets").GetValueAsUnsigned(0)
        if size <= 0 or num_buckets <= 0 or buckets == 0:
            return False
        t = self.valobj.GetType().GetUnqualifiedType()
        key_t = t.GetTemplateArgumentType(0)
        val_t = t.GetTemplateArgumentType(1)
        node_t = _find_type(
            self.valobj.GetTarget(), "QHashNode<%s, %s>" % (key_t.GetName(), val_t.GetName())
        )
        if not node_t.IsValid():
            return False
        self.node_t = node_t
        ps = _ptr_size(self.valobj)
        raw = _read(self.valobj, buckets, num_buckets * ps)
        for b in range(num_buckets):
            node = int.from_bytes(raw[b * ps : (b + 1) * ps], "little")
            guard = 0
            while node != 0 and node != d_addr and guard < 10000:
                self.nodes.append(node)
                nxt = _read(self.valobj, node, ps)
                node = int.from_bytes(nxt, "little") if len(nxt) == ps else 0
                guard += 1
            if len(self.nodes) >= size:
                break
        return False

    def num_children(self):
        return len(self.nodes)

    def get_child_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def get_child_at_index(self, i):
        if i < 0 or i >= len(self.nodes):
            return None
        return _pair_child(self.valobj, self.nodes[i], self.node_t, i)


# ---------------------------------------------------------------- QSet
class QSetProvider:
    """QSet<T> — это QHash<T, QHashDummyValue> в поле q_hash. Показываем сами ключи,
    а не вложенный хеш с пустыми значениями."""

    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.inner = None
        q = _raw(self.valobj).GetChildMemberWithName("q_hash")
        if not q.IsValid():
            return False
        inner = QHashProvider(q, None)
        inner.update()
        if getattr(inner, "nodes", None) and getattr(inner, "node_t", None):
            self.inner = inner
        return False

    def num_children(self):
        return len(self.inner.nodes) if self.inner else 0

    def get_child_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def get_child_at_index(self, i):
        if not self.inner or i < 0 or i >= len(self.inner.nodes):
            return None
        obj = self.inner.valobj
        node = obj.CreateValueFromAddress("node", self.inner.nodes[i], self.inner.node_t)
        key = node.GetChildMemberWithName("key")
        if not key.IsValid():
            return None
        return obj.CreateValueFromAddress("[%d]" % i, key.GetLoadAddress(), key.GetType())


# ---------------------------------------------------------------- QSharedPointer
class QSharedPointerProvider:
    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.value = _raw(self.valobj).GetChildMemberWithName("value")
        return False

    def num_children(self):
        return 1 if self.value.IsValid() and self.value.GetValueAsUnsigned(0) else 0

    def get_child_index(self, name):
        return 0 if name == "*" else -1

    def get_child_at_index(self, i):
        if i != 0 or not self.num_children():
            return None
        pointee = self.value.GetType().GetPointeeType()
        return self.valobj.CreateValueFromAddress(
            "*", self.value.GetValueAsUnsigned(0), pointee
        )


def qsharedpointer_summary(valobj, internal_dict):
    v = valobj.GetNonSyntheticValue().GetChildMemberWithName("value")
    addr = v.GetValueAsUnsigned(0) if v.IsValid() else 0
    return "nullptr" if addr == 0 else "-> 0x%x" % addr


# ---------------------------------------------------------------- QVariant
# Идентификаторы QMetaType для типов, которые реально хочется видеть в панели.
_VARIANT_TYPES = {
    1: "bool", 2: "int", 3: "uint", 4: "qlonglong", 5: "qulonglong",
    6: "double", 10: "QString", 11: "QStringList", 12: "QByteArray",
    38: "float",
}


def _variant_value(valobj):
    d = valobj.GetNonSyntheticValue().GetChildMemberWithName("d")
    if not d.IsValid():
        return None, None
    tid = d.GetChildMemberWithName("type").GetValueAsUnsigned(0)
    name = _VARIANT_TYPES.get(tid)
    if not name:
        return None, tid
    t = _find_type(valobj.GetTarget(), name)
    if not t.IsValid():
        return None, tid
    data = d.GetChildMemberWithName("data")
    addr = data.GetLoadAddress()
    if d.GetChildMemberWithName("is_shared").GetValueAsUnsigned(0):
        # QVariant::PrivateShared: ptr лежит первым полем
        shared = data.GetChildMemberWithName("shared").GetValueAsUnsigned(0)
        raw = _read(valobj, shared, _ptr_size(valobj))
        if len(raw) != _ptr_size(valobj):
            return None, tid
        addr = int.from_bytes(raw, "little")
    return valobj.CreateValueFromAddress("value", addr, t), tid


def qvariant_summary(valobj, internal_dict):
    v, tid = _variant_value(valobj)
    if v is None:
        return "тип %s (форматтер не знает)" % tid
    return "%s (%s)" % (v.GetSummary() or v.GetValue(), v.GetType().GetName())


class QVariantProvider:
    def __init__(self, valobj, internal_dict):
        self.valobj = valobj

    def update(self):
        self.value, _ = _variant_value(self.valobj)
        return False

    def num_children(self):
        return 1 if self.value else 0

    def get_child_index(self, name):
        return 0 if name == "value" else -1

    def get_child_at_index(self, i):
        return self.value if i == 0 else None


# ---------------------------------------------------------------- QDateTime
def qdatetime_summary(valobj, internal_dict):
    import datetime

    d = valobj.GetChildMemberWithName("d")
    data = d.GetChildMemberWithName("data") if d.IsValid() else lldb.SBValue()
    msecs = data.GetChildMemberWithName("msecs") if data.IsValid() else lldb.SBValue()
    if not msecs.IsValid():
        return "(long-form, msecs недоступны)"
    ms = msecs.GetValueAsSigned(0)
    stamp = datetime.datetime.utcfromtimestamp(ms / 1000.0)
    # Qt хранит время «как на стенных часах» выбранной зоны — зону не интерпретируем
    return "%s (msecs=%d)" % (stamp.strftime("%Y-%m-%d %H:%M:%S"), ms)


# ---------------------------------------------------------------- регистрация
def __lldb_init_module(debugger, internal_dict):
    m = __name__
    cmds = [
        'type summary add -F %s.qstring_summary QString' % m,
        'type summary add -F %s.qbytearray_summary QByteArray' % m,
        'type synthetic add -x "^QVector<.+>$" -l %s.QVectorProvider' % m,
        'type synthetic add -x "^QList<.+>$"   -l %s.QListProvider' % m,
        'type synthetic add -x "^QStringList$" -l %s.QListProvider' % m,
        'type synthetic add -x "^QMap<.+>$"    -l %s.QMapProvider' % m,
        'type synthetic add -x "^QHash<.+>$"   -l %s.QHashProvider' % m,
        'type summary add -x "^QVector<.+>$" -F %s.qcontainer_summary -e' % m,
        'type summary add -x "^QList<.+>$"   -F %s.qcontainer_summary -e' % m,
        'type summary add -x "^QStringList$" -F %s.qcontainer_summary -e' % m,
        'type summary add -x "^QMap<.+>$"    -F %s.qcontainer_summary -e' % m,
        'type summary add -x "^QHash<.+>$"   -F %s.qcontainer_summary -e' % m,
        'type synthetic add -x "^QSet<.+>$"  -l %s.QSetProvider' % m,
        'type summary add -x "^QSet<.+>$"    -F %s.qcontainer_summary -e' % m,
        'type synthetic add -x "^QSharedPointer<.+>$" -l %s.QSharedPointerProvider' % m,
        'type summary add -x "^QSharedPointer<.+>$"   -F %s.qsharedpointer_summary -e' % m,
        'type synthetic add -F %s.QVariantProvider QVariant' % m,
        'type summary add -F %s.qvariant_summary QVariant' % m,
        'type summary add -F %s.qdatetime_summary QDateTime' % m,
    ]
    for c in cmds:
        debugger.HandleCommand(c)
