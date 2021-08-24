import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'package:zapdart/utils.dart';
import 'package:zapdart/widgets.dart';

import 'paydb.dart';
import 'cryptocurrency.dart';
import 'prefs.dart';

class AssetScreen extends StatelessWidget {
  final List<ZcAsset> assets;

  AssetScreen(this.assets);

  Widget _listItem(BuildContext context, int n) {
    var asset = assets[n];
    return ListTile(
        title: Text('${asset.symbol}'),
        subtitle: Text(
            'name: ${asset.name}, status: ${asset.status}, minimum confirmations: ${asset.minConfs}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(itemBuilder: _listItem, itemCount: assets.length),
    );
  }
}

class OrderScreen extends StatefulWidget {
  final ZcBrokerOrder order;

  OrderScreen(this.order);

  @override
  State<OrderScreen> createState() => _OrderScreenState(order);
}

class _OrderScreenState extends State<OrderScreen> {
  ZcBrokerOrder _order;

  _OrderScreenState(this._order);

  Future<void> _accept() async {
    showAlertDialog(context, 'accepting..');
    var res = await zcOrderAccept(_order.token);
    Navigator.pop(context);
    if (res.error == PayDbError.None)
      setState(() => _order = res.order);
    else
      alert(context, 'error', 'failed to accept order');
  }

  Future<void> _update() async {
    showAlertDialog(context, 'updating..');
    var res = await zcOrderStatus(_order.token);
    Navigator.pop(context);
    if (res.error == PayDbError.None)
      setState(() => _order = res.order);
    else
      alert(context, 'error', 'failed to update order status');
  }

  void _launchURL(String? url) async {
    if (url != null)
      await canLaunch(url) ? await launch(url) : throw 'Could not launch $url';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: ListView(children: [
      ListTile(title: Text('ID'), subtitle: Text('${_order.token}')),
      ListTile(title: Text('Market'), subtitle: Text('${_order.market}')),
      ListTile(
          title: Text('Amount'),
          subtitle: Text('${_order.baseAmount} ${_order.baseAsset}')),
      ListTile(
          title: Text('Price'),
          subtitle: Text('${_order.quoteAmount} ${_order.quoteAsset}')),
      ListTile(title: Text('Date'), subtitle: Text('${_order.date}')),
      ListTile(title: Text('Expiry'), subtitle: Text('${_order.expiry}')),
      ListTile(title: Text('Recipient'), subtitle: Text('${_order.recipient}')),
      ListTile(
          title: Text('Status'),
          subtitle: Text('${describeEnum(_order.status)}')),
      _order.paymentUrl != null
          ? ListTile(
              title: Text('Payment URL'),
              subtitle: Text('${_order.paymentUrl}'),
              onTap: () => _launchURL(_order.paymentUrl))
          : SizedBox(),
      _order.status == ZcOrderStatus.created
          ? ListTile(
              title: raisedButton(onPressed: _accept, child: Text('Accept')))
          : SizedBox(),
      ListTile(title: raisedButton(onPressed: _update, child: Text('Update'))),
    ]));
  }
}

class OrdersScreen extends StatefulWidget {
  final List<ZcBrokerOrder> orders;

  OrdersScreen(this.orders);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  Future<void> _orderTap(ZcBrokerOrder order) async {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => OrderScreen(order)));
  }

  Widget _listItem(BuildContext context, int n) {
    var order = widget.orders[n];
    return ListTile(
        title: Text('${order.token}'),
        subtitle: Text(
            'market: ${order.market}, amount: ${order.baseAmount} ${order.baseAsset}'),
        onTap: () => _orderTap(order));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
          itemBuilder: _listItem, itemCount: widget.orders.length),
    );
  }
}

class QuoteScreen extends StatefulWidget {
  final ZcMarket market;
  final ZcOrderbook orderbook;

  QuoteScreen(this.market, this.orderbook);

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _withdrawalAddressController = TextEditingController();

  var _quote = '-';
  var _amount = Decimal.zero;
  var _address = '-';
  var _testnet = true;

  @override
  void initState() {
    super.initState();

    // Start listening to changes.
    _amountController.addListener(_updateQuote);
    _withdrawalAddressController.addListener(_updateAddress);

    // get testnet
    Prefs.testnetGet().then((value) => _testnet = value);
  }

  Decimal _calcTotalPrice(Decimal amount) {
    var filled = Decimal.zero;
    var totalPrice = Decimal.zero;
    var n = 0;
    while (amount > filled) {
      if (n >= widget.orderbook.asks.length) {
        return Decimal.fromInt(-1);
      }
      var rate = widget.orderbook.asks[n].rate;
      var quantity = widget.orderbook.asks[n].quantity;
      var quantityToUse = quantity;
      if (quantityToUse > amount - filled) quantityToUse = amount - filled;
      filled += quantityToUse;
      totalPrice += quantityToUse * rate;
      if (filled == amount) {
        return totalPrice;
      }
      n++;
    }
    return Decimal.fromInt(-1);
  }

  void _updateQuote() {
    var quote = '-';
    var amount = Decimal.zero;
    var value = Decimal.tryParse(_amountController.text);
    if (value != null && value > Decimal.zero) {
      amount = value;
      var totalPrice = _calcTotalPrice(value);
      if (totalPrice < Decimal.zero)
        quote = 'not enough liquidity';
      else
        quote =
            '$value ${widget.market.baseSymbol} = $totalPrice ${widget.market.quoteSymbol}';
    }
    setState(() {
      _quote = quote;
      _amount = amount;
    });
  }

  void _updateAddress() {
    var addr = '-';
    var res = addressValidate(
        widget.market.baseSymbol, _testnet, _withdrawalAddressController.text);
    if (res.result) addr = _withdrawalAddressController.text;
    setState(() => _address = addr);
  }

  void _orderCreate() async {
    if (_formKey.currentState == null) return;
    if (_formKey.currentState!.validate()) {
      showAlertDialog(context, 'creating order..');
      var res = await zcOrderCreate(
          widget.market.symbol, ZcMarketSide.bid, _amount, _address);
      Navigator.pop(context);
      if (res.error == PayDbError.None) {
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => OrderScreen(res.order)));
      } else
        alert(context, 'error', 'failed to create order');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Form(
            key: _formKey,
            child: Container(
                padding: EdgeInsets.all(10),
                child: Column(children: [
                  Text(_quote),
                  Text('Send $_amount to $_address'),
                  TextFormField(
                      controller: _amountController,
                      decoration: InputDecoration(labelText: 'Amount'),
                      keyboardType: TextInputType.numberWithOptions(
                          signed: false, decimal: true),
                      validator: (value) {
                        if (value == null) return 'Please enter a value';
                        var d = Decimal.tryParse(value);
                        if (d == null) return 'Invalid value';
                        if (d <= Decimal.fromInt(0))
                          return 'Please enter a value greater then 0';
                        if (_calcTotalPrice(d) < Decimal.fromInt(0))
                          return 'Insufficient liquidity';
                        return null;
                      }),
                  TextFormField(
                      controller: _withdrawalAddressController,
                      decoration: InputDecoration(labelText: 'Wallet Address'),
                      keyboardType: TextInputType.text,
                      validator: (value) {
                        if (value == null) return 'Please enter a value';
                        var res = addressValidate(
                            widget.market.baseSymbol, _testnet, value);
                        if (!res.result) return res.reason;
                        return null;
                      }),
                  raisedButton(
                      onPressed: _orderCreate, child: Text('Create Order'))
                ]))));
  }
}

class MarketScreen extends StatefulWidget {
  final List<ZcMarket> markets;

  MarketScreen(this.markets);

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  Future<void> _marketTap(ZcMarket market) async {
    showAlertDialog(context, 'querying..');
    var res = await zcOrderbook(market.symbol);
    Navigator.pop(context);
    if (res.error == PayDbError.None) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => QuoteScreen(market, res.orderbook)));
    }
  }

  Widget _listItem(BuildContext context, int n) {
    var market = widget.markets[n];
    return ListTile(
        title: Text('${market.symbol}'),
        subtitle:
            Text('status: ${market.status}, min trade: ${market.minTrade}'),
        onTap: () => _marketTap(market));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
          itemBuilder: _listItem, itemCount: widget.markets.length),
    );
  }
}