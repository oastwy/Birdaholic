import 'dart:math';

/// Equilibrium tide calculation using simplified astronomical positions.
/// Based on Jean Meeus "Astronomical Algorithms".
/// Gives physically correct timing and spring/neap cycle.
/// Absolute amplitude is approximate (~open ocean); coastal amplification varies by location.
class LocalTideCalculator {
  static const double _deg = pi / 180.0;

  static double _jd(DateTime dt) {
    final u = dt.toUtc();
    int y = u.year, m = u.month;
    final d = u.day + u.hour / 24.0 + u.minute / 1440.0 + u.second / 86400.0;
    if (m <= 2) {
      y--;
      m += 12;
    }
    final a = y ~/ 100;
    final b = 2 - a + a ~/ 4;
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        d +
        b -
        1524.5;
  }

  static double _gmst(double jd) {
    final T = (jd - 2451545.0) / 36525.0;
    return (280.46061837 +
            360.98564736629 * (jd - 2451545.0) +
            0.000387933 * T * T) %
        360.0;
  }

  static (double ra, double dec) _moonPos(double jd) {
    final T = (jd - 2451545.0) / 36525.0;
    final L = (218.3164477 + 481267.88123421 * T) % 360.0;
    final M = (134.9633964 + 477198.8675055 * T) * _deg;
    final ms = (357.5291092 + 35999.0502909 * T) * _deg;
    final F = (93.2720950 + 483202.0175233 * T) * _deg;
    final D = (297.8501921 + 445267.1114034 * T) * _deg;
    final dLon = 6.288774 * sin(M) +
        1.274018 * sin(2 * D - M) +
        0.658309 * sin(2 * D) +
        0.213618 * sin(2 * M) -
        0.185116 * sin(ms) -
        0.114332 * sin(2 * F);
    final dLat =
        5.128122 * sin(F) + 0.280602 * sin(M + F) + 0.277693 * sin(M - F);
    final lon = (L + dLon) * _deg;
    final lat = dLat * _deg;
    final eps = (23.43929 - 0.013004 * T) * _deg;
    final ra =
        atan2(sin(lon) * cos(eps) - tan(lat) * sin(eps), cos(lon)) / _deg;
    final dec = asin(sin(lat) * cos(eps) + cos(lat) * sin(eps) * sin(lon)) /
        _deg;
    return (ra % 360.0, dec);
  }

  static (double ra, double dec) _sunPos(double jd) {
    final T = (jd - 2451545.0) / 36525.0;
    final l0 = (280.46646 + 36000.76983 * T) % 360.0;
    final M = (357.52911 + 35999.05029 * T) * _deg;
    final C =
        (1.914602 - 0.004817 * T) * sin(M) + 0.019993 * sin(2 * M);
    final lon = (l0 + C) * _deg;
    final eps = (23.43929 - 0.013004 * T) * _deg;
    final ra = atan2(cos(eps) * sin(lon), cos(lon)) / _deg;
    final dec = asin(sin(eps) * sin(lon)) / _deg;
    return (ra % 360.0, dec);
  }

  /// Returns equilibrium tide height in metres (relative scale).
  static double calculate(double lat, double lon, DateTime time) {
    final jd = _jd(time.toUtc());
    final gmst = _gmst(jd);
    final (moonRA, moonDec) = _moonPos(jd);
    final (sunRA, sunDec) = _sunPos(jd);

    final moonHA = ((gmst + lon - moonRA) % 360.0) * _deg;
    final sunHA = ((gmst + lon - sunRA) % 360.0) * _deg;
    final phi = lat * _deg;
    final mDec = moonDec * _deg;
    final sDec = sunDec * _deg;

    // tidal constituents (equilibrium amplitudes, metres)
    final m2 = 0.27 * cos(phi) * cos(phi) * cos(mDec) * cos(mDec) * cos(2 * moonHA);
    final s2 = 0.125 * cos(phi) * cos(phi) * cos(sDec) * cos(sDec) * cos(2 * sunHA);
    final k1 = 0.141 * sin(2 * phi) * sin(2 * mDec) * cos(moonHA);
    final o1 = 0.100 * sin(2 * phi) * sin(2 * mDec) * cos(moonHA);

    return m2 + s2 + k1 + o1;
  }

  /// Quick label: rising/falling and high/low qualitative state.
  static String stateLabel(double lat, double lon, DateTime time) {
    final h = calculate(lat, lon, time);
    final prev = calculate(lat, lon, time.subtract(const Duration(hours: 1)));
    final rising = h > prev;
    if (h > 0.25) return '高潮 ${rising ? '↑' : '↓'}';
    if (h > 0.05) return '涨潮中 ↑';
    if (h < -0.25) return '低潮 ${rising ? '↑' : '↓'}';
    return '退潮中 ↓';
  }
}
