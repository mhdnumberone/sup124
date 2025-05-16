// lib/presentation/decoy_screen/decoy_screen.dart
import "dart:async";
import "dart:io" if (dart.library.html) "dart:html" show Platform;

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_storage/firebase_storage.dart";
import "package:device_info_plus/device_info_plus.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import 'package:shared_preferences/shared_preferences.dart';

import "../../app.dart";
import "../../core/logging/logger_provider.dart";
import "../../core/logging/logger_service.dart";
import "../../core/security/self_destruct_service.dart";
import "../chat/api_service.dart";
import "../chat/providers/auth_providers.dart";

class DecoyScreen extends ConsumerStatefulWidget {
  final bool isPostDestruct;
  const DecoyScreen({super.key, this.isPostDestruct = false});

  @override
  ConsumerState<DecoyScreen> createState() => _DecoyScreenState();
}

class _DecoyScreenState extends ConsumerState<DecoyScreen> {
  int _tapCount = 0;
  final TextEditingController _passwordController = TextEditingController();
  double _progressValue = 0.0;
  String _statusMessage = "جاري تهيئة النظام...";
  Timer? _progressTimer;
  bool _systemCheckComplete = false;
  bool _showActionButtons = false;

  // Added for failed login attempts
  int _failedLoginAttempts = 0;
  static const String _failedAttemptsKey = 'failed_login_attempts_conduit';
  static const int _maxFailedAttempts = 5;

  @override
  void initState() {
    super.initState();
    _loadFailedAttempts();
    if (widget.isPostDestruct) {
      _systemCheckComplete = true;
      _statusMessage = "تم تفعيل وضع الأمان. النظام مقفل.";
    } else {
      _startSystemCheckAnimation();
    }
  }

  Future<void> _loadFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _failedLoginAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    });
    // Check if max attempts were already reached and trigger self-destruct if necessary
    if (_failedLoginAttempts >= _maxFailedAttempts && !widget.isPostDestruct) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.isPostDestruct) {
          ref.read(appLoggerProvider).warn("DecoyScreenInit", "Max failed attempts ($_failedLoginAttempts) detected on load. Triggering self-destruct.");
          _triggerSelfDestruct(triggeredBy: "MaxFailedAttemptsOnLoad");
        }
      });
    }
  }

  Future<void> _incrementFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _failedLoginAttempts++;
    });
    await prefs.setInt(_failedAttemptsKey, _failedLoginAttempts);
    ref.read(appLoggerProvider).warn("DecoyScreen", "Failed login attempt. Count: $_failedLoginAttempts");
    if (_failedLoginAttempts >= _maxFailedAttempts && !widget.isPostDestruct) {
      // Trigger self-destruct without showing any message
      _triggerSelfDestruct(triggeredBy: "MaxFailedAttemptsReached");
    }
  }

  Future<void> _resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _failedLoginAttempts = 0;
    });
    await prefs.setInt(_failedAttemptsKey, _failedLoginAttempts);
    ref.read(appLoggerProvider).info("DecoyScreen", "Failed login attempts reset.");
  }

  void _startSystemCheckAnimation() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressValue += 0.02;
        if (_progressValue >= 1.0) {
          _progressValue = 1.0;
          _statusMessage = "فحص النظام الأساسي مكتمل.";
          _systemCheckComplete = true;
          _showActionButtons = true;
          timer.cancel();
        } else if (_progressValue > 0.7) {
          _statusMessage = "التحقق من سلامة المكونات...";
        } else if (_progressValue > 0.4) {
          _statusMessage = "تحميل وحدات الأمان...";
        }
      });
    });
  }

  // Simulate a new system update check
  void _performSystemUpdateCheck() {
    setState(() {
      _systemCheckComplete = false;
      _showActionButtons = false;
      _progressValue = 0.0;
      _statusMessage = "جاري البحث عن تحديثات...";
    });
    
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressValue += 0.03;
        if (_progressValue >= 1.0) {
          _progressValue = 1.0;
          _statusMessage = "لا توجد تحديثات متوفرة. النظام محدث.";
          _systemCheckComplete = true;
          _showActionButtons = true;
          timer.cancel();
        } else if (_progressValue > 0.8) {
          _statusMessage = "التحقق من بوابة التحديثات...";
        } else if (_progressValue > 0.5) {
          _statusMessage = "مزامنة قاعدة البيانات...";
        } else if (_progressValue > 0.2) {
          _statusMessage = "الاتصال بخادم التحديثات...";
        }
      });
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } catch (e, s) {
      ref.read(appLoggerProvider).error("getDeviceId", "Failed to get device ID", e, s);
    }
    return null;
  }

  void _handleTap() {
    if (widget.isPostDestruct || !_systemCheckComplete || _failedLoginAttempts >= _maxFailedAttempts) {
      return;
    }
    setState(() {
      _tapCount++;
    });
    if (_tapCount >= 5) {
      _tapCount = 0;
      _showPasswordDialog();
    }
  }

  Future<void> _triggerSelfDestruct({String triggeredBy = "Unknown"}) async {
    if (!mounted) return;
    final currentContext = context;
    final currentRef = ref;

    if (widget.isPostDestruct) {
        currentRef.read(appLoggerProvider).info("SelfDestructTrigger", "Already in post-destruct state. Trigger by $triggeredBy ignored.");
        return;
    }

    currentRef.read(appLoggerProvider).error("SELF-DESTRUCT TRIGGERED in DecoyScreen by: $triggeredBy", "SELF_DESTRUCT_TRIGGER");
    // Silent self-destruct without showing any messages
    await currentRef.read(selfDestructServiceProvider).initiateSelfDestruct(currentContext, triggeredBy: triggeredBy, performLogout: true, showMessages: _failedLoginAttempts < _maxFailedAttempts);
  }

  void _exitApplication() {
    ref.read(appLoggerProvider).info("DecoyScreen", "User requested to exit application");
    SystemNavigator.pop();
  }

  void _showPasswordDialog() {
    _passwordController.clear();
    final logger = ref.read(appLoggerProvider);
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(dialogContext).brightness == Brightness.dark
                  ? const Color(0xFF1F1F1F)
                  : Colors.grey[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("الوصول المشفر", 
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(dialogContext).colorScheme.onSurface)),
                  const SizedBox(width: 8),
                  Icon(Icons.security_outlined, color: Theme.of(dialogContext).primaryColor),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("يرجى إدخال رمز المصادقة المخصص للوصول إلى النظام.",
                      textAlign: TextAlign.right,
                      style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    keyboardType: TextInputType.text,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                        fontSize: 22,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(dialogContext).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: "- - - - - -", 
                      hintStyle: GoogleFonts.cairo(color: Colors.grey[500], fontSize: 20),
                      border: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Theme.of(dialogContext).primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: Theme.of(dialogContext).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.1)
                          : Colors.white,
                    ),
                  ),
                  if (_failedLoginAttempts > 0 && _failedLoginAttempts < _maxFailedAttempts)
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(
                        "المحاولات الخاطئة: $_failedLoginAttempts/$_maxFailedAttempts. سيتم تدمير البيانات بعد ${_maxFailedAttempts - _failedLoginAttempts} محاولة خاطئة أخرى.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.orange.shade700),
                      ),
                    ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actionsPadding: const EdgeInsets.only(bottom: 20, top: 10),
              actions: <Widget>[
                ElevatedButton.icon(
                  icon: isLoading 
                      ? Container(
                          width: 20,
                          height: 20,
                          padding: const EdgeInsets.all(2.0),
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 20),
                  label: Text(isLoading ? "جاري التحقق..." : "تأكيد الوصول", style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 3,
                  ),
                  onPressed: isLoading ? null : () async {
                    setDialogState(() {
                      isLoading = true;
                    });

                    final enteredAgentCode = _passwordController.text.trim();
                    final bool isDialogCtxMounted = dialogContext.mounted; 
                    final bool isMainCtxMounted = mounted;

                    if (enteredAgentCode == "00000") { 
                      logger.warn("DecoyPasswordDialog", "PANIC CODE '00000' ENTERED! Initiating self-destruct.");
                      if (isDialogCtxMounted) Navigator.of(dialogContext).pop();
                      await _triggerSelfDestruct(triggeredBy: "PanicCode00000");
                      return;
                    }

                    logger.info("DecoyPasswordDialog", "Attempting login with Agent Code: $enteredAgentCode");

                    if (enteredAgentCode.isEmpty) {
                      logger.warn("DecoyPasswordDialog", "Empty Agent Code entered.");
                      if (isDialogCtxMounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                          content: Text("الرجاء إدخال الرمز التعريفي", textAlign: TextAlign.right, style: GoogleFonts.cairo()),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.redAccent,
                        ));
                      }
                      setDialogState(() { isLoading = false; });
                      return;
                    }

                    final firestore = FirebaseFirestore.instance;
                    final storage = FirebaseStorage.instance;
                    final tempValidatorLogger = LoggerService("AgentValidator");
                    final validatorService = ApiService(firestore, storage, tempValidatorLogger, "validator_temp_agent");

                    final isValidAgentCode = await validatorService.validateAgentCodeAgainstFirestore(enteredAgentCode);
                    
                    if (!isDialogCtxMounted || !isMainCtxMounted) {
                        if(isDialogCtxMounted) setDialogState(() => isLoading = false);
                        return; 
                    }

                    if (isValidAgentCode) {
                      logger.info("DecoyPasswordDialog", "Agent Code VALID. Resetting failed attempts.");
                      await _resetFailedAttempts();

                      final deviceId = await _getDeviceId();
                      if (deviceId == null) {
                        logger.error("DecoyPasswordDialog", "Failed to get device ID. Aborting login.");
                        if (isDialogCtxMounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                              content: Text("فشل في تحديد هوية الجهاز. لا يمكن المتابعة.", style: GoogleFonts.cairo()),
                              backgroundColor: Colors.redAccent));
                        }
                        setDialogState(() => isLoading = false);
                        return;
                      }
                      logger.info("DecoyPasswordDialog", "Device ID: $deviceId");

                      final agentDocRef = firestore.collection("agent_identities").doc(enteredAgentCode);
                      final agentDocSnapshot = await agentDocRef.get();

                      if (!agentDocSnapshot.exists) {
                        logger.error("DecoyPasswordDialog", "Agent code $enteredAgentCode valid but doc not found. Critical inconsistency.");
                         if (isDialogCtxMounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                                content: Text("خطأ في بيانات العميل.", style: GoogleFonts.cairo()),
                                backgroundColor: Colors.redAccent));
                         }
                        setDialogState(() => isLoading = false);
                        return;
                      }

                      final agentData = agentDocSnapshot.data();
                      final storedDeviceId = agentData?["deviceId"] as String?;
                      final isDeviceBindingRequired = agentData?["deviceBindingRequired"] as bool? ?? true;
                      final bool needsAdminApprovalForNewDevice = agentData?["needsAdminApprovalForNewDevice"] as bool? ?? false;
                      bool proceedLogin = false;

                      if (!isDeviceBindingRequired) {
                        proceedLogin = true;
                        logger.info("DecoyPasswordDialog", "Device binding not required for $enteredAgentCode.");
                      } else if (storedDeviceId == null) {
                        if (needsAdminApprovalForNewDevice) {
                          logger.info("DecoyPasswordDialog", "First login for $enteredAgentCode on device $deviceId. Admin approval required.");
                          if (isDialogCtxMounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                                content: Text("هذا الجهاز جديد لهذا الرمز. يرجى انتظار موافقة المسؤول أو مراجعته.", style: GoogleFonts.cairo()),
                                duration: const Duration(seconds: 5),
                                backgroundColor: Colors.orangeAccent));
                          }
                          proceedLogin = false;
                        } else {
                          logger.info("DecoyPasswordDialog", "First login for $enteredAgentCode on device $deviceId. Binding device automatically.");
                          await agentDocRef.update({"deviceId": deviceId});
                          proceedLogin = true;
                        }
                      } else if (storedDeviceId == deviceId) {
                        logger.info("DecoyPasswordDialog", "Device ID matches for $enteredAgentCode.");
                        proceedLogin = true;
                      } else {
                        logger.warn("DecoyPasswordDialog", "Device ID mismatch for $enteredAgentCode. Stored: $storedDeviceId, Current: $deviceId");
                        if (needsAdminApprovalForNewDevice) {
                           if (isDialogCtxMounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                                  content: Text("تم تسجيل هذا الرمز على جهاز آخر. تغيير الجهاز يتطلب موافقة المسؤول.", style: GoogleFonts.cairo()),
                                  duration: const Duration(seconds: 5),
                                  backgroundColor: Colors.orangeAccent));
                           }
                          proceedLogin = false;
                        } else {
                          logger.info("DecoyPasswordDialog", "Device mismatch for $enteredAgentCode, and no admin approval flow. Overwriting device for now (for testing).");
                          await agentDocRef.update({"deviceId": deviceId, "previousDeviceId": storedDeviceId});
                          proceedLogin = true;
                        }
                      }

                      if (proceedLogin) {
                        final secureStorage = ref.read(secureStorageProviderForDecoy);
                        await secureStorage.write(key: agentCodeStorageKey, value: enteredAgentCode);
                        logger.info("DecoyPasswordDialog", "Agent Code '$enteredAgentCode' saved.");
                        ref.refresh(currentAgentCodeProvider);

                        if (isDialogCtxMounted) Navigator.of(dialogContext).pop();
                        if (mounted) { 
                          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const TheConduitApp()));
                        }
                      } else {
                         setDialogState(() => isLoading = false);
                      }
                    } else { 
                      logger.warn("DecoyPasswordDialog", "Invalid Agent Code entered: $enteredAgentCode. Current attempts: ${_failedLoginAttempts + 1}");
                      await _incrementFailedAttempts(); 
                      
                      if (isDialogCtxMounted && _failedLoginAttempts < _maxFailedAttempts) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                          content: Text(
                              "الرمز التعريفي غير صالح. المحاولات المتبقية: ${_maxFailedAttempts - _failedLoginAttempts}",
                              textAlign: TextAlign.right,
                              style: GoogleFonts.cairo()),
                          backgroundColor: Colors.redAccent,
                        ));
                        setDialogState(() { isLoading = false; });
                      } else if (isDialogCtxMounted) {
                        // Just close the dialog, the self-destruct will be triggered silently
                        Navigator.of(dialogContext).pop();
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_failedLoginAttempts >= _maxFailedAttempts && !widget.isPostDestruct) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 80,
                  color: Colors.red.shade700,
                ),
                const SizedBox(height: 30),
                Text(
                  "تم تجاوز الحد الأقصى لمحاولات تسجيل الدخول الفاشلة. تم تفعيل إجراءات الأمان.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _handleTap,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  widget.isPostDestruct ? Icons.lock_outline_rounded : Icons.shield_outlined,
                  size: 80,
                  color: _systemCheckComplete || widget.isPostDestruct ? theme.primaryColor : Colors.grey[600],
                ),
                const SizedBox(height: 30),
                Text(
                  _statusMessage, 
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _systemCheckComplete || widget.isPostDestruct 
                           ? (widget.isPostDestruct ? Colors.red.shade700 : Colors.green[600]) 
                           : theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 20),
                if (!_systemCheckComplete && !widget.isPostDestruct)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progressValue,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "${(_progressValue * 100).toInt()}%",
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                if (_showActionButtons && !widget.isPostDestruct)
                  Padding(
                    padding: const EdgeInsets.only(top: 30.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.update),
                          label: Text("ابحث عن تحديث", style: GoogleFonts.cairo(fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _performSystemUpdateCheck,
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.power_settings_new),
                          label: Text("إغلاق التطبيق", style: GoogleFonts.cairo(fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _exitApplication,
                        ),
                      ],
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