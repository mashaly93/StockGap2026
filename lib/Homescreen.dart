import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'OrderScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class Homescreen extends StatelessWidget {
   Homescreen({super.key});

  static const String routeName = 'Homescreen';
  final codeController = TextEditingController();
  final passwordController = TextEditingController();

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
                        Image.asset(
                          'assets/images/back.png',
                          scale: 2.7,
                        ),

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
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xff0050c0), width: 1.5),
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
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xff0050c0), width: 1.5),
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
                              try {
                                await FirebaseAuth.instance.signInWithEmailAndPassword(
                                  email: codeController.text.trim(),
                                  password: passwordController.text.trim(),
                                );

                                // 🔥 هنا نحفظ البيانات في Firestore
                                final user = FirebaseAuth.instance.currentUser;

                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user!.uid)
                                    .set({
                                  'name': "Pharmacy 1",
                                  'email': user.email,
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Login Success 🚀")),
                                );

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OrderScreen(
                                      storeCode: user.email ?? "",
                                    ),
                                  ),
                                );

                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Error: $e")),
                                );
                              }
                            }

                            // 🔥 هنا تغيير لون الزر
                            ,style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff0050c0), // لون الزر
                              foregroundColor: Colors.white,            // لون النص
                              padding: const EdgeInsets.symmetric(
                                horizontal: 40,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),

                            child: const Text("Login"),
                          )
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
}