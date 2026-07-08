import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'OrderScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Homescreen extends StatefulWidget {
  Homescreen({super.key});

  static const String routeName = 'Homescreen';

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {
  final codeController = TextEditingController();

  final passwordController = TextEditingController();

  @override
  void dispose() {
    codeController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkLogin();
    });
  }

  bool isCheckingLogin = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Card Container
                Card(
                  elevation: 8,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      children: [
                        // Logo
                        Image.asset('assets/images/back.png', scale: 2.7),

                        const SizedBox(height: 12),

                        const Text(
                          "Stock Gap Generator",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff0050c0),
                          ),
                        ),

                        const SizedBox(height: 25),

                        // Store Code
                        TextFormField(
                          controller: codeController,
                          decoration: InputDecoration(
                            labelText: 'Pharmacy / Store Code',
                            prefixIcon: const Icon(Icons.store),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xff0050c0),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        // Password
                        TextFormField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xff0050c0),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () async {
                              setState(() => isLoading = true);

                              try {
                                print("LOGIN START");

                                final username = codeController.text.trim();
                                final password = passwordController.text.trim();

                                if (username.isEmpty || password.isEmpty) {
                                  setState(() => isLoading = false);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Enter username and password"),
                                    ),
                                  );
                                  return;
                                }


                                print("BEFORE FIREBASE QUERY");


                                final result = await FirebaseFirestore.instance
                                    .collection("users")
                                    .where(
                                  "username",
                                  isEqualTo: username,
                                )
                                    .limit(1)
                                    .get(
                                  const GetOptions(
                                    source: Source.server,
                                  ),
                                );


                                print("AFTER FIREBASE QUERY");


                                if (result.docs.isEmpty) {
                                  setState(() => isLoading = false);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("User not found"),
                                    ),
                                  );

                                  return;
                                }


                                final doc = result.docs.first;
                                final data = doc.data();

                                final docRef = doc.reference;


                                // PASSWORD
                                if (data["password"] != password) {

                                  setState(() => isLoading = false);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Wrong password"),
                                    ),
                                  );

                                  return;
                                }



                                // ACTIVE
                                if (data["active"] != true) {

                                  setState(() => isLoading = false);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Account disabled"),
                                    ),
                                  );

                                  return;
                                }



                                // EXPIRE DATE

                                final expireDate =
                                (data["expireDate"] as Timestamp).toDate();


                                if (DateTime.now().isAfter(expireDate)) {

                                  setState(() => isLoading = false);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Subscription expired"),
                                    ),
                                  );

                                  return;
                                }



                                // DEVICE SYSTEM

                                final prefs = await SharedPreferences.getInstance();


                                String deviceId =
                                    prefs.getString("deviceId") ?? "";


                                if (deviceId.isEmpty) {

                                  deviceId =
                                      DateTime.now()
                                          .microsecondsSinceEpoch
                                          .toString();


                                  await prefs.setString(
                                    "deviceId",
                                    deviceId,
                                  );
                                }



                                List devices = List.from(
                                  data["devices"] ?? [],
                                );



                                // تنظيف القيم الغلط
                                devices = devices
                                    .where((d)=> d is Map)
                                    .map((d)=> Map<String,dynamic>.from(d))
                                    .toList();



                                // هل الجهاز موجود؟
                                bool exists = devices.any(
                                      (d)=> d["deviceId"] == deviceId,
                                );



                                int maxDevices =
                                    data["maxDevices"] ?? 1;



                                if (!exists) {

                                  if (devices.length >= maxDevices) {

                                    setState(() => isLoading = false);


                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content:
                                        Text("Too many devices logged in"),
                                      ),
                                    );

                                    return;
                                  }



                                  devices.add({

                                    "deviceId": deviceId,

                                    "deviceName":
                                    "Flutter Windows",

                                    "loginTime":
                                    DateTime.now()
                                        .toIso8601String(),

                                  });


                                  await docRef.update({

                                    "devices": devices,

                                  });

                                }



                                // SAVE LOGIN

                                await prefs.setString(
                                  "username",
                                  username,
                                );



                                setState(() => isLoading = false);



                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OrderScreen(
                                      storeCode: username,
                                      expireDate: data["expireDate"],
                                    ),
                                  ),
                                );



                              } catch(e,stack){

                                print(e);
                                print(stack);

                                setState(() => isLoading = false);


                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString(),
                                    ),
                                  ),
                                );
                              }
                            },

                            // 🔥 هنا تغيير لون الزر
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xff0050c0,
                              ), // لون الزر
                              foregroundColor: Colors.white, // لون النص
                              padding: const EdgeInsets.symmetric(
                                horizontal: 40,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),

                            child: isLoading
                                ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                                : const Text("Login"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> checkLogin() async {

    if(isCheckingLogin) return;

    isCheckingLogin = true;


    final prefs =
    await SharedPreferences.getInstance();


    final savedUser =
    prefs.getString("username");


    // لا تدخل تلقائي حاليا
    // خلي المستخدم يعمل Login كل مرة


    isCheckingLogin = false;
  }

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    String? deviceId = prefs.getString("deviceId");

    if (deviceId == null || deviceId.isEmpty) {
      deviceId = prefs.getString("deviceId") ?? "";

      if (deviceId.isEmpty) {
        deviceId = UniqueKey().toString();
        await prefs.setString("deviceId", deviceId);
      }
      await prefs.setString("deviceId", deviceId);
    }

    return deviceId;
  }
  Future<void> registerDevice({
    required String deviceId,
    required String deviceName,
    required List devices,
    required int maxDevices,
    required DocumentReference docRef,
    required Function(String) show,
    required VoidCallback stopLoading,
  }) async {

    bool alreadyExists =
    devices.any((d) => d["deviceId"] == deviceId);

    if (!alreadyExists) {
      if (devices.length >= maxDevices) {
        stopLoading();
        show("Too many devices logged in");
        return;
      }

      devices.add({
        "deviceId": deviceId,
        "deviceName": deviceName,
        "loginTime": DateTime.now().toIso8601String(),
      });


      await docRef.update({
        "devices": devices,
      });

    }
  }
}
