import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:conductor_app/utils/utils.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as djwt;
import 'package:basic_utils/basic_utils.dart';
import 'dart:ui' as ui;

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  _PaymentPageState createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  ImageProvider? _textAsImageProvider;
  final TextEditingController _priceController = TextEditingController();
  String _qrData = "";
  String _secretKey = "";
  String? _token = "";
  bool _isLoading = false;
  String? username = "";
  String? destinationAlert = "";
  get center => null;
  @override
  void initState() {
    super.initState();
    _onPageRendered();
  }

  bool clicked = false;

  void _onPageRendered() async {
    setState(() {
      _isLoading = true;
    });
    // Add your code here that needs to be executed when the page renders
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    destinationAlert = prefs.getString('destination_alert');
    username = prefs.getString('username');

    _secretKey = (await getPrivateKey()).toString();
    if (_secretKey == "null") {
      _updateSecretKey();
    } else {
      setState(() {
        _isLoading = false;
        clicked = false;
      });
    }
  }

  void _updateSecretKey() async {
    setState(() {
      _isLoading = true;
    });
    final pair = generateRSAkeyPair(exampleSecureRandom());
    final public = pair.publicKey;
    final private = pair.privateKey;
    _secretKey = CryptoUtils.encodeRSAPrivateKeyToPem(private);
    final String baseUrl = dotenv.env['SITE_URL'] ?? '';
    final String secretKeyUpdate = '$baseUrl/api/update-secret-key/';
    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SITE_URL not found in .env')),
      );
    }
    final response = await http.post(
      Uri.parse(secretKeyUpdate),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $_token',
      },
      body: jsonEncode(
          {'secret_key': CryptoUtils.encodeRSAPublicKeyToPem(public)}),
    );
    if (response.statusCode == 200) {
      await storePrivateKey(CryptoUtils.encodeRSAPrivateKeyToPem(private));
      setState(() {
        _isLoading = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update secret key')),
      );

      setState(() {
        _isLoading = false;
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  bool _isInvalidPrice = false; // New flag to track if the price is invalid
  void _generateQR() async {
    FocusScope.of(context).unfocus();
    // Validate price before generating QR
    final price = double.tryParse(_priceController.text) ?? 0;

    if (price <= 0) {
      FocusScope.of(context).unfocus();
      // If price is invalid, reset the QR data and display the error message
      setState(() {
        _isInvalidPrice = true;
        _qrData = ""; // Clear any previously generated QR code
        _textAsImageProvider =
            null; // Clear previously generated QR image if any
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.sentiment_dissatisfied, color: Colors.red),
              const SizedBox(width: 10), // Adds spacing between icon and text
              Expanded(
                child: const Text(
                  'Invalid price. Please enter a value greater than 0.',
                  style: TextStyle(fontSize: 16), // Optional: Adjust font size
                ),
              ),
            ],
          ),
          backgroundColor: Colors.black87,
          behavior:
              SnackBarBehavior.floating, // Makes it look like a floating bar
          duration: const Duration(seconds: 3), // Display duration
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // Rounded corners
          ),
        ),
      );
      return;
    }

    ImageProvider gg = await _generateTextImage(_priceController.text);
    setState(() {
      // Get the current date (used as the 'issued at' and 'expiration' date)
      final now = DateTime.now();
      clicked = true;
      // Define the payload (claims)
      final payload = {
        'sub':
            username, // 'sub' is typically used for the subject (user's identity)
        'price': _priceController.text, // Price in the payload
        'iat': now
            .toUtc()
            .millisecondsSinceEpoch, // 'iat' (Issued At) is the timestamp of when the JWT was created in UTC
        'exp': now
            .add(const Duration(minutes: 15))
            .toUtc()
            .millisecondsSinceEpoch, // 'exp' (Expiration) is 1 hour from now
      };
      final jwt = djwt.JWT(payload);
      final privateKey = djwt.RSAPrivateKey(_secretKey);
      final token = jwt.sign(privateKey, algorithm: djwt.JWTAlgorithm.RS256);
      _qrData = token.toString();
      _textAsImageProvider = gg;
    });
    // Ensure keyboard stays hidden after QR generation
    FocusScope.of(context).unfocus();
  }

  Future<ImageProvider> _generateTextImage(String text) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color.fromARGB(255, 236, 0, 0),
          fontSize: 60,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 10.0,
              color: Colors.white,
              offset: Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final width = textPainter.width;
    final height = textPainter.height;
    textPainter.paint(canvas, const Offset(0, 0));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    return MemoryImage(pngBytes);
  }

  // Function to show the confirmation dialog
  void _showConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm QR Code Generation'),
          content: const Text('Are you sure you want to generate new QR code?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _generateQR(); // Call the function after confirmation
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            
            const SizedBox(height: 50),
            const Text(
              "Caution : Don't generate multiple QR codes.",
              style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
              textAlign: TextAlign.left,
            ),
            // Main outer box
            const SizedBox(height: 20),
            Container(
              margin:
                  const EdgeInsets.all(10.0), // Adds margin around the main box
              padding: const EdgeInsets.all(
                  12.0), // Adds padding inside the main box
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade300,
                    blurRadius: 6.0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Align content to start
                children: [
                  // Label or additional content can go here if needed
                  const Text(
                    'Enter Price',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Sub-box for price entry
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5.0, vertical: 5.0), // Reduced padding
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100, // Slight grey background
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                          color:
                              Colors.grey.shade300), // Border for the sub-box
                    ),
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelStyle: TextStyle(
                          fontSize: 22.0,
                          fontWeight: FontWeight.bold,
                        ),
                        hintText: 'Enter the price to generate QR code',
                        hintStyle: TextStyle(
                          fontSize: 15.0,
                          fontStyle: FontStyle.italic,
                          color: Color.fromARGB(255, 158, 158, 158),
                        ),
                        border: InputBorder.none, // No default border
                      ),
                      keyboardType: TextInputType.number,
                      style:
                          const TextStyle(fontSize: 15.0), // Larger text style
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                clicked ? _showConfirmationDialog(context) : _generateQR();
              },
              child: const Text('Generate QR Code'),
            ),
            const SizedBox(height: 20),
            _qrData.isNotEmpty
                ? QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 200.0,
                    embeddedImage: _textAsImageProvider,
                  )
                : Container(),
          ],
        ),
      ),
    );
  }
}
