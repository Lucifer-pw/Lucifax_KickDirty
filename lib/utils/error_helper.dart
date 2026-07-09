String getCleanErrorMessage(dynamic error) {
  if (error == null) return 'Terjadi kesalahan.';
  
  final errorStr = error.toString();
  final errorStrLower = errorStr.toLowerCase();

  // Allow custom sanitized part-specific errors to pass through
  if (errorStrLower.contains('akses ditolak (bagian:')) {
    return errorStr;
  }

  // 1. Handle permission denied (403 Forbidden)
  if (errorStrLower.contains('permission-denied') || 
      errorStrLower.contains('permission_denied') || 
      errorStrLower.contains('insufficient permissions') || 
      errorStrLower.contains('missing or insufficient permissions')) {
    return 'Status 403 Forbidden: Akses Ditolak';
  }

  // 2. Handle network/offline errors
  if (errorStr.contains('network-request-failed') || 
      errorStr.contains('unavailable') || 
      errorStr.contains('network error') ||
      errorStr.contains('failed host lookup')) {
    return 'Gagal memuat data. Periksa koneksi internet Anda.';
  }

  // 3. Default fallback
  return 'Terjadi kesalahan. Silakan coba beberapa saat lagi.';
}
