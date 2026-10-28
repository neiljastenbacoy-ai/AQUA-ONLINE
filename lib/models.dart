import 'constants.dart';

class OrderItem {
  String type; // 'refill' | 'buy'
  int qty;
  OrderItem({required this.type, required this.qty});

  factory OrderItem.fromJson(json) =>
      OrderItem(type: json['type'] as String, qty: (json['qty'] as num).toInt());
  Map<String, dynamic> toJson() => {'type': type, 'qty': qty};
}

class Address {
  String id, label, street, brgy, city, landmark;
  bool def;
  double? lat, lng; // map pin — nullable so old saved addresses keep working
  Address({
    required this.id,
    required this.label,
    required this.street,
    required this.brgy,
    this.city = '',
    this.landmark = '',
    this.def = false,
    this.lat,
    this.lng,
  });

  String get line => [street, brgy, city].where((s) => s.isNotEmpty).join(', ');
  bool get hasPin => lat != null && lng != null;

  factory Address.fromJson(json) => Address(
        id: json['id'] as String,
        label: (json['label'] ?? 'Home') as String,
        street: (json['street'] ?? '') as String,
        brgy: (json['brgy'] ?? '') as String,
        city: (json['city'] ?? '') as String,
        landmark: (json['landmark'] ?? '') as String,
        def: (json['def'] ?? false) as bool,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'label': label, 'street': street, 'brgy': brgy, 'city': city,
        'landmark': landmark, 'def': def, 'lat': lat, 'lng': lng,
      };
}

class AddrLine {
  String label, line;
  double? lat, lng; // snapshot of the delivery pin at order placement
  AddrLine({required this.label, required this.line, this.lat, this.lng});
  bool get hasPin => lat != null && lng != null;
  factory AddrLine.fromJson(json) => AddrLine(
      label: (json['label'] ?? '') as String,
      line: (json['line'] ?? '') as String,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble());
  Map<String, dynamic> toJson() => {'label': label, 'line': line, 'lat': lat, 'lng': lng};
}

class Issue {
  String type, text;
  int ts;
  Issue({required this.type, this.text = '', required this.ts});
  factory Issue.fromJson(json) => Issue(
      type: (json['type'] ?? '') as String,
      text: (json['text'] ?? '') as String,
      ts: (json['ts'] ?? 0) as int);
  Map<String, dynamic> toJson() => {'type': type, 'text': text, 'ts': ts};
}

class Customer {
  String name, phone;
  Customer({required this.name, this.phone = ''});
  factory Customer.fromJson(json) =>
      Customer(name: (json['name'] ?? 'Customer') as String, phone: (json['phone'] ?? '') as String);
  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

class Order {
  String id;
  List<OrderItem> items;
  double total;
  AddrLine address;
  String time, note, pay;
  int createdAt;
  int status; // 0..4
  bool cancelled;
  List<int?> stamps;
  String? owner;
  Customer cust;
  String? riderId;
  Map<String, double>? prices; // price snapshot at placement
  Map<String, int>? stock; // {c,w} consumed at placement
  bool restored;
  bool byRider;
  Issue? issue;
  bool seedH;
  Order({
    required this.id,
    required this.items,
    required this.total,
    required this.address,
    this.time = 'asap',
    this.note = '',
    this.pay = 'cod',
    required this.createdAt,
    required this.stamps,
    this.owner,
    required this.cust,
    this.riderId,
    this.prices,
    this.stock,
    this.status = 0,
    this.cancelled = false,
    this.restored = false,
    this.byRider = false,
    this.issue,
    this.seedH = false,
  });

  double unitPrice(String t, double refillPrice, double buyPrice) {
    if (prices != null && prices![t] != null) return prices![t]!;
    return t == 'refill' ? refillPrice : buyPrice;
  }

  bool isSeed() => seedH && owner == 'other';

  factory Order.fromJson(json) => Order(
        id: json['id'] as String,
        items: (json['items'] as List).map(OrderItem.fromJson).toList(),
        total: (json['total'] as num?)?.toDouble() ?? 0,
        address: AddrLine.fromJson(json['address'] ?? {}),
        time: (json['time'] ?? 'asap') as String,
        note: (json['note'] ?? '') as String,
        pay: (json['pay'] ?? 'cod') as String,
        createdAt: (json['createdAt'] ?? 0) as int,
        status: (json['status'] ?? 0) as int,
        cancelled: (json['cancelled'] ?? false) as bool,
        stamps: ((json['stamps'] ?? []) as List)
            .map((x) => (x is num) ? x.toInt() : null)
            .toList(),
        owner: json['owner'] as String?,
        cust: Customer.fromJson(json['cust'] ?? {}),
        riderId: json['riderId'] as String?,
        prices: json['prices'] == null
            ? null
            : (json['prices'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        stock: json['stock'] == null
            ? null
            : (json['stock'] as Map)
                .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        restored: (json['restored'] ?? false) as bool,
        byRider: (json['byRider'] ?? false) as bool,
        issue: json['issue'] == null ? null : Issue.fromJson(json['issue']),
        seedH: (json['seedH'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items.map((i) => i.toJson()).toList(),
        'total': total,
        'address': address.toJson(),
        'time': time,
        'note': note,
        'pay': pay,
        'createdAt': createdAt,
        'status': status,
        'cancelled': cancelled,
        'stamps': stamps,
        'owner': owner,
        'cust': cust.toJson(),
        'riderId': riderId,
        'prices': prices,
        'stock': stock,
        'restored': restored,
        'byRider': byRider,
        'issue': issue?.toJson(),
        'seedH': seedH,
      };
}

class Notif {
  String id, title, body, type;
  int ts;
  bool read;
  String? orderId, rid;
  Notif({required this.id, this.type = 'info', this.title = '', this.body = '', required this.ts, this.read = false, this.orderId, this.rid});
  factory Notif.fromJson(json) => Notif(
        id: json['id'] as String? ?? uid(),
        type: (json['type'] ?? 'info') as String,
        title: (json['title'] ?? '') as String,
        body: (json['body'] ?? '') as String,
        ts: (json['ts'] ?? DateTime.now().millisecondsSinceEpoch) as int,
        read: (json['read'] ?? false) as bool,
        orderId: json['orderId'] as String?,
        rid: json['rid'] as String?,
      );
  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'title': title, 'body': body, 'ts': ts, 'read': read, 'orderId': orderId, 'rid': rid};
}

class Rider {
  String id, name, phone, email, vehicle, plate, available, pass;
  bool active;
  Rider({
    required this.id,
    required this.name,
    this.phone = '',
    required this.email,
    this.vehicle = 'Motorcycle',
    this.plate = '',
    this.available = 'available',
    this.active = true,
    this.pass = 'aqua1234',
  });
  factory Rider.fromJson(json) => Rider(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        phone: (json['phone'] ?? '') as String,
        email: (json['email'] ?? '') as String,
        vehicle: (json['vehicle'] ?? 'Motorcycle') as String,
        plate: (json['plate'] ?? '') as String,
        available: (json['available'] ?? 'available') as String,
        active: (json['active'] ?? true) as bool,
        pass: (json['pass'] ?? 'aqua1234') as String,
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'phone': phone, 'email': email,
        'vehicle': vehicle, 'plate': plate, 'available': available, 'active': active,
        'pass': pass,
      };
}

class Account {
  String name, phone, email;
  Account({required this.name, required this.email, this.phone = ''});
  factory Account.fromJson(json) => Account(
      name: (json['name'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      phone: (json['phone'] ?? '') as String);
  Map<String, dynamic> toJson() => {'name': name, 'email': email, 'phone': phone};
}

class Product {
  double price;
  String desc;
  bool active;
  Product({required this.price, required this.desc, this.active = true});
  factory Product.fromJson(json) => Product(
      price: (json['price'] as num?)?.toDouble() ?? 0,
      desc: (json['desc'] ?? '') as String,
      active: (json['active'] ?? true) as bool);
  Map<String, dynamic> toJson() => {'price': price, 'desc': desc, 'active': active};
}

class Station {
  String name, phone, address, open, close;
  bool accepting, autoAssign;
  double? lat, lng; // station map pin — route start for live tracking
  Station({
    this.name = 'AQUA Purified Water Station',
    this.phone = '+63 917 800 1200',
    this.address = 'Villanueva, Misamis Oriental',
    this.open = '07:00',
    this.close = '19:00',
    this.accepting = true,
    this.autoAssign = true,
    this.lat = 8.6069,
    this.lng = 124.8222,
  });
  factory Station.fromJson(json) => Station(
        name: (json['name'] ?? 'AQUA Purified Water Station') as String,
        phone: (json['phone'] ?? '+63 917 800 1200') as String,
        address: (json['address'] ?? 'Villanueva, Misamis Oriental') as String,
        open: (json['open'] ?? '07:00') as String,
        close: (json['close'] ?? '19:00') as String,
        accepting: (json['accepting'] ?? true) as bool,
        autoAssign: (json['autoAssign'] ?? true) as bool,
        lat: (json['lat'] as num?)?.toDouble() ?? 8.6069,
        lng: (json['lng'] as num?)?.toDouble() ?? 124.8222,
      );
  Map<String, dynamic> toJson() => {
        'name': name, 'phone': phone, 'address': address, 'open': open, 'close': close,
        'accepting': accepting, 'autoAssign': autoAssign, 'lat': lat, 'lng': lng,
      };
}

class InvItem {
  int qty, low;
  InvItem({required this.qty, required this.low});
  factory InvItem.fromJson(json) => InvItem(
      qty: (json['qty'] ?? 0) as int, low: (json['low'] ?? 0) as int);
  Map<String, dynamic> toJson() => {'qty': qty, 'low': low};
}

class InvLog {
  int ts;
  String kind, item, note;
  int delta;
  InvLog({required this.ts, required this.kind, required this.item, required this.delta, this.note = ''});
  factory InvLog.fromJson(json) => InvLog(
      ts: (json['ts'] ?? 0) as int,
      kind: (json['kind'] ?? '') as String,
      item: (json['item'] ?? '') as String,
      delta: (json['delta'] ?? 0) as int,
      note: (json['note'] ?? '') as String);
  Map<String, dynamic> toJson() => {'ts': ts, 'kind': kind, 'item': item, 'delta': delta, 'note': note};
}

class AppSettings {
  String theme; // system|light|dark
  bool notify, autoDeliver;
  // autoDeliver is a demo convenience — online orders advance by real rider
  // and admin actions, so it defaults off on fresh installs.
  AppSettings({this.theme = 'system', this.notify = true, this.autoDeliver = false});
  factory AppSettings.fromJson(json) => AppSettings(
      theme: (json['theme'] ?? 'system') as String,
      notify: (json['notify'] ?? true) as bool,
      autoDeliver: (json['autoDeliver'] ?? false) as bool);
  Map<String, dynamic> toJson() => {'theme': theme, 'notify': notify, 'autoDeliver': autoDeliver};
}

class CartItem {
  String type;
  int qty;
  CartItem({required this.type, required this.qty});
  factory CartItem.fromJson(json) =>
      CartItem(type: json['type'] as String, qty: (json['qty'] as num).toInt());
  Map<String, dynamic> toJson() => {'type': type, 'qty': qty};
}

class Draft {
  String type = 'refill';
  int qty = 1;
  String? addressId;
  String time = 'asap';
  String note = '';
  String pay = 'cod';
  Draft({this.type = 'refill', this.qty = 1, this.addressId, this.time = 'asap', this.note = '', this.pay = 'cod'});
  factory Draft.fromJson(json) => Draft(
        type: (json['type'] ?? 'refill') as String,
        qty: (json['qty'] ?? 1) as int,
        addressId: json['addressId'] as String?,
        time: (json['time'] ?? 'asap') as String,
        note: (json['note'] ?? '') as String,
        pay: (json['pay'] ?? 'cod') as String,
      );
  Map<String, dynamic> toJson() =>
      {'type': type, 'qty': qty, 'addressId': addressId, 'time': time, 'note': note, 'pay': pay};
}

class InvItemDef {
  final String name, sub, unit;
  const InvItemDef(this.name, this.sub, this.unit);
}
