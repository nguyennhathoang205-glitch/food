import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_http.dart' as http;

import 'chat_assistant.dart';
import 'login_screen.dart';
import 'services/offline_service.dart';
import 'phone_frame_wrapper.dart';
import 'core/app_colors.dart';
import 'core/app_config.dart';
import 'core/app_session.dart';
import 'models/models.dart';
import 'features/home/home_screen.dart';
import 'features/scan/scan_screen.dart';
import 'features/stats/statistics_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/profile/profile_screen.dart';

void main() {
  runApp(const FoodScanApp());
}

// ============================================================
// CONFIG & SESSION
// ============================================================

const Color primary = AppColors.primary;
const Color primaryDark = AppColors.primaryDark;
const Color primaryLight = AppColors.primaryLight;
const Color accent = AppColors.accent;
const Color background = AppColors.background;
const Color gold = AppColors.gold;

String backendBaseUrl = AppConfig.baseUrl;

String get currentUserKey => AppSession.currentUserKey;
set currentUserKey(String v) => AppSession.currentUserKey = v;

VoidCallback? get appLogout => AppSession.appLogout;
set appLogout(VoidCallback? v) => AppSession.appLogout = v;

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    appLogout = _logout;
    _init();
  }

  Future<void> _init() async {
    await http.AuthSession.load();
    if (http.AuthSession.token != null) {
      try {
        final r = await http.get(Uri.parse('$backendBaseUrl/api/auth/me'));
        if (r.statusCode == 401) {
          await http.AuthSession.clear();
        }
      } catch (_) {}
    }
    if (http.AuthSession.userId != null) {
      currentUserKey = http.AuthSession.userId!;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _logout() async {
    await http.AuthSession.clear();
    currentUserKey = 'demo-user';
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (http.AuthSession.token == null) {
      return LoginScreen(
        baseUrl: backendBaseUrl,
        onAuthed: () {
          currentUserKey = http.AuthSession.userId!;
          setState(() {});
        },
      );
    }
    return FoodScanShell(key: ValueKey(currentUserKey));
  }
}

// Android Emulator:
// const String backendBaseUrl =
//     'http://10.0.2.2:5000';

// ============================================================
// APP
// ============================================================

class FoodScanApp extends StatelessWidget {
  const FoodScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodScan AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          iconTheme: const IconThemeData(color: accent),
          titleTextStyle: GoogleFonts.plusJakartaSans(
            color: accent,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      builder: (context, child) => PhoneFrameWrapper(child: child ?? const SizedBox()),
      home: const AuthGate(),
    );
  }
}

// ============================================================
// MODELS (Clean Architecture)
// Extracted to lib/models/models.dart:
// - Nutrition, TotalNutrition
// - Detection
// - FoodOption
// - UserProfile
// - MealEntry
// ============================================================

// ============================================================
// API
// ============================================================

class ApiService {
  static Future<UserProfile> getProfile() async {
    final response = await http.get(
      Uri.parse('$backendBaseUrl/api/profile/$currentUserKey'),
    );

    if (response.statusCode != 200) {
      throw Exception('Không tải được hồ sơ');
    }

    final data = jsonDecode(response.body);

    return UserProfile.fromJson(data['profile']);
  }

  static Future<UserProfile> saveProfile(UserProfile profile) async {
    final response = await http.post(
      Uri.parse('$backendBaseUrl/api/profile/$currentUserKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(profile.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Không lưu được hồ sơ');
    }

    final data = jsonDecode(response.body);

    return UserProfile.fromJson(data['profile']);
  }

  static Future<List<MealEntry>> getMeals() async {
    final response = await http.get(
      Uri.parse('$backendBaseUrl/api/meals/$currentUserKey'),
    );

    if (response.statusCode != 200) {
      throw Exception('Không tải được nhật ký');
    }

    final data = jsonDecode(response.body);

    final List<dynamic> raw = data['meals'] ?? [];

    return raw.map((item) => MealEntry.fromJson(item)).toList();
  }

  static Future<MealEntry> addMeal(MealEntry meal) async {
    final response = await http.post(
      Uri.parse('$backendBaseUrl/api/meals'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(meal.toJson(currentUserKey)),
    );

    if (response.statusCode != 200) {
      throw Exception('Không lưu được bữa ăn');
    }

    final data = jsonDecode(response.body);

    return MealEntry.fromJson(data['meal']);
  }

  static Future<void> deleteMeal(int id) async {
    final response = await http.delete(
      Uri.parse('$backendBaseUrl/api/meals/$id'),
    );

    if (response.statusCode != 200) {
      throw Exception('Không xóa được món');
    }
  }

  static Future<MealEntry> updateMeal(MealEntry meal) async {
    final response = await http.put(
      Uri.parse('$backendBaseUrl/api/meals/${meal.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(meal.toJson(currentUserKey)),
    );

    if (response.statusCode != 200) {
      throw Exception('Không cập nhật được món');
    }

    final data = jsonDecode(response.body);
    return MealEntry.fromJson(data['meal']);
  }

  static Future<List<FoodOption>> getFoods() async {
    final response = await http.get(Uri.parse('$backendBaseUrl/api/foods'));

    if (response.statusCode != 200) {
      throw Exception('Không tải được danh sách món');
    }

    final data = jsonDecode(response.body);

    final List<dynamic> raw = data['foods'] ?? [];

    return raw.map((item) => FoodOption.fromJson(item)).toList();
  }

  static Future<void> sendFeedback({
    required Detection prediction,
    required FoodOption corrected,
  }) async {
    final response = await http.post(
      Uri.parse('$backendBaseUrl/api/feedback'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_key': currentUserKey,

        'predicted_class_id': prediction.classId,

        'predicted_name': prediction.nameVi,

        'predicted_confidence': prediction.confidence,

        'corrected_class_id': corrected.id,

        'corrected_name': corrected.nameVi,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Không gửi được phản hồi');
    }
  }

  static Future<Map<String, List<String>>> getHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$backendBaseUrl/api/health/$currentUserKey'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final h = data['health'] as Map<String, dynamic>? ?? {};
        final allergies = (h['allergies'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final conditions = (h['conditions'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return {'allergies': allergies, 'conditions': conditions};
      }
    } catch (_) {}
    return {'allergies': [], 'conditions': []};
  }
}

// ============================================================
// MAIN SHELL
// ============================================================

class FoodScanShell extends StatefulWidget {
  const FoodScanShell({super.key});

  @override
  State<FoodScanShell> createState() => _FoodScanShellState();
}

class _FoodScanShellState extends State<FoodScanShell> {
  int selectedIndex = 0;

  UserProfile profile = UserProfile.empty();

  List<MealEntry> mealEntries = [];

  List<String> userAllergies = [];

  List<String> userConditions = [];

  bool loading = true;

  // Ket qua /detect gan nhat, dung lam ngu canh cho tro ly chat AI.
  Map<String, dynamic>? lastScanContext;

  void setLastScanContext(Map<String, dynamic> data) {
    setState(() {
      lastScanContext = data;
    });
  }

  @override
  void initState() {
    super.initState();

    loadData();
  }

  Future<void> loadData() async {
    setState(() {
      loading = true;
    });

    try {
      final results = await Future.wait([
        ApiService.getProfile(),
        ApiService.getMeals(),
        ApiService.getHealth(),
      ]);

      if (!mounted) {
        return;
      }

      final health = results[2] as Map<String, List<String>>;

      setState(() {
        profile = withAccountName(results[0] as UserProfile);
        mealEntries = results[1] as List<MealEntry>;
        userAllergies = health['allergies'] ?? [];
        userConditions = health['conditions'] ?? [];
        loading = false;
      });

      syncOfflineMeals();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được dữ liệu từ backend.')),
      );
    }
  }

  /// Ho so moi tao tren server mang ten mac dinh "Nguoi dung Food Scan" ->
  /// hien ten tai khoan da dang ky thay vi ten chung chung.
  UserProfile withAccountName(UserProfile p) {
    final accountName = (http.AuthSession.name ?? '').trim();
    final isDefault = p.displayName.trim().isEmpty ||
        p.displayName == 'Người dùng Food Scan';
    if (isDefault && accountName.isNotEmpty) {
      return p.copyWith(displayName: accountName);
    }
    return p;
  }

  // Lam moi im lang (khong hien spinner toan man hinh) - dung cho keo-de-lam-moi.
  Future<void> refreshData() async {
    try {
      final results = await Future.wait([
        ApiService.getProfile(),
        ApiService.getMeals(),
        ApiService.getHealth(),
      ]);

      if (!mounted) {
        return;
      }

      final health = results[2] as Map<String, List<String>>;

      setState(() {
        profile = withAccountName(results[0] as UserProfile);
        mealEntries = results[1] as List<MealEntry>;
        userAllergies = health['allergies'] ?? [];
        userConditions = health['conditions'] ?? [];
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không làm mới được dữ liệu.')),
      );
    }
  }

  Future<void> addMeal(MealEntry meal) async {
    try {
      final saved = await ApiService.addMeal(meal);

      if (!mounted) {
        return;
      }

      setState(() {
        mealEntries.insert(0, saved);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: accent,
          content: Text('Đã thêm ${saved.name} vào ${saved.mealType}'),
        ),
      );
      syncOfflineMeals();
    } catch (e) {
      if (!mounted) {
        return;
      }

      if (isNetworkError(e)) {
        await OfflineMealQueue.enqueue(meal.toJson(AppSession.currentUserKey));
        if (!mounted) {
          return;
        }
        setState(() {
          mealEntries.insert(0, meal);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB45309),
            content: Text(
              'Không có mạng - đã lưu "${meal.name}" trên máy, sẽ tự đồng bộ khi có mạng.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Không lưu được bữa ăn. Máy chủ từ chối lưu, thử lại sau.'),
        ),
      );
    }
  }

  /// Gui cac bua da luu offline len may chu (goi khi mo app hoac co mang lai).
  Future<void> syncOfflineMeals() async {
    final synced = await OfflineMealQueue.flush((m) async {
      final res = await http.post(
        Uri.parse('$backendBaseUrl/api/meals'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(m),
      );
      return res.statusCode == 200;
    });
    if (synced > 0 && mounted) {
      await loadData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: accent,
          content: Text('Đã đồng bộ $synced bữa ăn lưu offline.'),
        ),
      );
    }
  }
  Future<void> removeMeal(MealEntry meal) async {
    if (meal.id == null) {
      return;
    }

    try {
      await ApiService.deleteMeal(meal.id!);

      if (!mounted) {
        return;
      }

      setState(() {
        mealEntries.removeWhere((e) => e.id == meal.id);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Không xóa được món.')));
    }
  }

  Future<void> updateMeal(MealEntry meal) async {
    if (meal.id == null) {
      return;
    }

    try {
      final saved = await ApiService.updateMeal(meal);

      if (!mounted) {
        return;
      }

      setState(() {
        final idx = mealEntries.indexWhere((e) => e.id == meal.id);
        if (idx != -1) {
          mealEntries[idx] = saved;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primary,
          content: Text('Đã cập nhật "${saved.name}" (${saved.portionG}g)'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không cập nhật được bữa ăn.')),
      );
    }
  }

  Future<void> saveProfile(UserProfile value) async {
    try {
      final saved = await ApiService.saveProfile(value);

      if (!mounted) {
        return;
      }

      setState(() {
        profile = withAccountName(saved);
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu hồ sơ.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Không lưu được hồ sơ.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    final pages = [
      HomeScreen(
        entries: mealEntries,
        profile: profile,
        userAllergies: userAllergies,
        userConditions: userConditions,
        onScan: () {
          setState(() {
            selectedIndex = 1;
          });
        },

        onJournal: () {
          setState(() {
            selectedIndex = 3;
          });
        },

        onRefresh: refreshData,

        onSaveProfile: saveProfile,

        onOpenProfile: () {
          setState(() {
            selectedIndex = 4;
          });
        },

        onManualAdd:
            ({
              required name,
              required mealType,
              required portionG,
              required calories,
              required proteinG,
              required fatG,
              required carbsG,
            }) => addMeal(
              MealEntry(
                name: name,
                mealType: mealType,
                time: DateTime.now(),
                portionG: portionG,
                calories: calories,
                proteinG: proteinG,
                fatG: fatG,
                carbsG: carbsG,
              ),
            ),
      ),

      ScanScreen(onAddMeal: addMeal, onScanResult: setLastScanContext),

      StatisticsScreen(entries: mealEntries, profile: profile),

      JournalScreen(
        entries: mealEntries,
        onDelete: removeMeal,
        onEdit: updateMeal,
        onReLog: addMeal,
      ),

      ProfileScreen(
        profile: profile,
        onSave: saveProfile,
        onHealthChanged: refreshData,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: selectedIndex, children: pages),

          FloatingHelpButton(
            backendBaseUrl: backendBaseUrl,
            scanContext: lastScanContext,
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: NavigationBar(
                height: 68,
                selectedIndex: selectedIndex,
                backgroundColor: Colors.white,
                indicatorColor: primary.withValues(alpha: 0.16),
                onDestinationSelected: (index) {
                  setState(() {
                    selectedIndex = index;
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded, color: primaryDark),
                    label: 'Trang chủ',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.qr_code_scanner_rounded),
                    selectedIcon: Icon(
                      Icons.center_focus_strong_rounded,
                      color: primaryDark,
                    ),
                    label: 'Quét món',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.insights_rounded),
                    selectedIcon: Icon(
                      Icons.insights_rounded,
                      color: primaryDark,
                    ),
                    label: 'Thống kê',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.book_outlined),
                    selectedIcon: Icon(
                      Icons.book_rounded,
                      color: primaryDark,
                    ),
                    label: 'Nhật ký',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(
                      Icons.person_rounded,
                      color: primaryDark,
                    ),
                    label: 'Hồ sơ',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
