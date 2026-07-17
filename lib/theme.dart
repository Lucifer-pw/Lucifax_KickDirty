import 'package:flutter/material.dart';

class AppTheme {
  // Global flag set by the ThemeProvider to toggle dynamic properties
  static bool isDarkMode = false;

  // Brand Colors (remain constant)
  static const Color primaryBlue = Color(0xFF0052CC); // Deep Sapphire Blue
  static const Color secondaryBlue = Color(0xFF00B0FF); // Sky Blue
  static const Color accentCyan = Color(0xFF00E5FF);

  // Dynamic Neutral Colors based on theme mode
  static Color get white => isDarkMode ? Color(0xFF1E293B) : Color(0xFFFFFFFF); // Slate 800 or White
  static Color get lightBlueBackground => isDarkMode ? Color(0xFF0F172A) : Color(0xFFF2F6FC); // Slate 900 or Soft Ice Blue
  static Color get darkBlueText => isDarkMode ? Color(0xFFF8FAFC) : Color(0xFF0A2540); // Slate 50 or Deep Navy
  static Color get lightGray => isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0); // Slate 700 or Light Gray
  static Color get borderGray => isDarkMode ? Color(0xFF475569) : Color(0xFFCBD5E1); // Slate 600 or Border Gray
  static Color get textGray => isDarkMode ? Color(0xFF94A3B8) : Color(0xFF64748B); // Slate 400 or Text Gray

  // Dynamic Gradients
  static LinearGradient get primaryGradient => LinearGradient(
    colors: [primaryBlue, secondaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get whiteBlueGradient => LinearGradient(
    colors: [white, lightBlueBackground],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static LinearGradient get cardGradient => LinearGradient(
    colors: [white, isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dynamic Shadow Styles
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: primaryBlue.withOpacity(isDarkMode ? 0.3 : 0.08),
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.04),
      blurRadius: 15,
      offset: Offset(0, 5),
    ),
  ];

  // Light Theme Data definition
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: Color(0xFFFFFFFF),
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        secondary: secondaryBlue,
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF0A2540)),
        titleTextStyle: TextStyle(
          color: Color(0xFF0A2540),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: Color(0xFF0A2540), fontSize: 32, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Color(0xFF0A2540), fontSize: 24, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Color(0xFF0A2540), fontSize: 18, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Color(0xFF0A2540), fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: Color(0xFF0A2540), fontSize: 16),
        bodyMedium: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        labelLarge: TextStyle(color: primaryBlue, fontSize: 14, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFFFFFFFF),
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Color(0xFFFFFFFF),
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardTheme(
        color: Color(0xFFFFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
    );
  }

  // Dark Theme Data definition
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: Color(0xFF0F172A), // Slate 900
      colorScheme: ColorScheme.dark(
        primary: primaryBlue,
        secondary: secondaryBlue,
        background: Color(0xFF0F172A),
        surface: Color(0xFF1E293B), // Slate 800
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFF8FAFC)),
        titleTextStyle: TextStyle(
          color: Color(0xFFF8FAFC),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: Color(0xFFF8FAFC), fontSize: 32, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Color(0xFFF8FAFC), fontSize: 24, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Color(0xFFF8FAFC), fontSize: 18, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Color(0xFFF8FAFC), fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: Color(0xFFF8FAFC), fontSize: 16),
        bodyMedium: TextStyle(color: Color(0xFF94A3B8), fontSize: 14), // Slate 400
        labelLarge: TextStyle(color: secondaryBlue, fontSize: 14, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF1E293B), // Slate 800
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFF475569)), // Slate 600
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFF334155)), // Slate 700
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: secondaryBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Color(0xFFFFFFFF),
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardTheme(
        color: Color(0xFF1E293B), // Slate 800
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Color(0xFF334155), width: 1), // Slate 700
        ),
      ),
    );
  }
}
