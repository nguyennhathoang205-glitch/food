import 'package:flutter/material.dart';

class PhoneFrameWrapper extends StatefulWidget {
  final Widget child;

  const PhoneFrameWrapper({super.key, required this.child});

  @override
  State<PhoneFrameWrapper> createState() => _PhoneFrameWrapperState();
}

class _PhoneFrameWrapperState extends State<PhoneFrameWrapper> {
  bool usePhoneFrame = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tren man hinh dien thoai that (chieu rong nho hon 560px) -> render nguyen ban 100%
        if (constraints.maxWidth <= 560) {
          return widget.child;
        }

        // Tren Desktop/Web rong hon 560px:
        if (!usePhoneFrame) {
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              Positioned(
                top: 14,
                right: 16,
                child: SafeArea(
                  child: _buildTogglePill(),
                ),
              ),
            ],
          );
        }

        final availableHeight = constraints.maxHeight;
        // Chuan ty le iPhone (khoang 393 x 852)
        const targetWidth = 400.0;
        final targetHeight = (availableHeight - 60).clamp(650.0, 860.0);

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: Stack(
            children: [
              // Background studio trang nha tren desktop
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [
                        Color(0xFF1E293B),
                        Color(0xFF090D16),
                      ],
                    ),
                  ),
                ),
              ),

              // Header bar tren desktop
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.apple_rounded, color: Color(0xFF10B981), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'FoodScan AI • Mobile View',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (constraints.maxWidth > 680) ...[
                              const SizedBox(width: 12),
                              const Flexible(
                                child: Text(
                                  'Màn hình chuẩn iPhone 16 Pro',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildTogglePill(),
                    ],
                  ),
                ),
              ),

              // Khung iPhone 16 Pro o giua man hinh
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 36, bottom: 20),
                  child: Container(
                    width: targetWidth,
                    height: targetHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(54),
                      border: Border.all(
                        color: const Color(0xFF334155),
                        width: 9,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: 48,
                          spreadRadius: 8,
                          offset: const Offset(0, 24),
                        ),
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          blurRadius: 60,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(44),
                      child: Stack(
                        children: [
                          // App View goc
                          Positioned.fill(child: widget.child),

                          // Dynamic Island gia lap tren iPhone
                          Positioned(
                            top: 10,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: IgnorePointer(
                                child: Container(
                                  width: 110,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(right: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFF1E293B),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Thanh dieu huong duoi Home Bar
                          Positioned(
                            bottom: 6,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: IgnorePointer(
                                child: Container(
                                  width: 130,
                                  height: 4.5,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTogglePill() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => usePhoneFrame = !usePhoneFrame),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                usePhoneFrame ? Icons.fullscreen_rounded : Icons.phone_iphone_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                usePhoneFrame ? 'Xem toàn màn hình' : 'Xem khung iPhone',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
