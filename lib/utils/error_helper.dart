String getCleanErrorMessage(dynamic error) {
  if (error == null) return 'Terjadi kesalahan.';
  
  final errorStr = error.toString().toLowerCase();

  // 1. Handle permission denied (403 Forbidden)
  if (errorStr.contains('permission-denied') || 
      errorStr.contains('permission_denied') || 
      errorStr.contains('insufficient permissions') || 
      errorStr.contains('missing or insufficient permissions')) {
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
