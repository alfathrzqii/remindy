import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/task_model.dart';
import '../services/notification_service.dart';

class TaskViewModel extends ChangeNotifier {
  List<TaskModel> _tasks = [];
  List<TaskModel> get tasks => _tasks;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  final NotificationService _notificationService = NotificationService();

  String _filterStatus = 'todo'; 
  String get filterStatus => _filterStatus;

  List<TaskModel> get filteredTasks {
    if (_filterStatus == 'todo') {
      return _tasks.where((t) => t.isCompleted == 0).toList();
    } else if (_filterStatus == 'completed') {
      return _tasks.where((t) => t.isCompleted == 1).toList();
    }
    return _tasks;
  }

  void setFilter(String status) {
    _filterStatus = status;
    notifyListeners(); // Update UI
  }

  // --- FUNGSI UTAMA ---
  Future<void> fetchTasks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _tasks = await DatabaseHelper.instance.readAllTasks();
    } catch (e) {
      debugPrint("Error fetching tasks: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Tambah Tugas + Jadwalkan Notifikasi
  Future<void> addTask(TaskModel task) async {
    // Simpan ke DB dan dapatkan ID baru
    final id = await DatabaseHelper.instance.createTask(task);
    
    // Buat object task baru dengan ID yang valid
    final newTask = task.copyWith(id: id);
    
    // Jadwalkan notifikasi
    await _notificationService.scheduleTaskNotification(newTask);
    
    await fetchTasks();
  }

  // [UPDATE] Edit Tugas + Reschedule Notifikasi
  Future<void> updateTask(TaskModel task) async {
    await DatabaseHelper.instance.updateTask(task);
    
    // Cancel notifikasi lama, lalu buat yang baru (Reset)
    if (task.id != null) {
      await _notificationService.cancelNotification(task.id!);
      await _notificationService.scheduleTaskNotification(task);
    }

    await fetchTasks();
  }

  // Hapus Tugas + Hapus Notifikasi
  Future<void> deleteTask(int id) async {
    await DatabaseHelper.instance.deleteTask(id);
    
    // Hapus notifikasi terkait
    await _notificationService.cancelNotification(id);
    
    await fetchTasks();
  }

  // Toggle Status + Atur Notifikasi
  Future<void> toggleTaskStatus(TaskModel task) async {
    final updatedTask = task.copyWith(
      isCompleted: task.isCompleted == 0 ? 1 : 0,
    );
    
    await DatabaseHelper.instance.updateTask(updatedTask);
    
    // Logic Notifikasi:
    if (updatedTask.isCompleted == 1) {
      // Jika selesai, matikan notifikasi agar tidak mengganggu
      if (task.id != null) await _notificationService.cancelNotification(task.id!);
    } else {
      // Jika batal selesai (unchecked), nyalakan lagi notifikasi
      await _notificationService.scheduleTaskNotification(updatedTask);
    }

    await fetchTasks();
  }

  // --- STATISTIK ---
  int get completedCount => _tasks.where((t) => t.isCompleted == 1).length;
  int get todoCount => _tasks.where((t) => t.isCompleted == 0).length;

  Map<String, double> getCategoryStats() {
    Map<String, double> stats = {};
    if (_tasks.isEmpty) return stats;

    for (var task in _tasks) {
      if (stats.containsKey(task.category)) {
        stats[task.category] = stats[task.category]! + 1;
      } else {
        stats[task.category] = 1;
      }
    }
    return stats;
  }
  
  // Reschedule All (Dipanggil saat Booting / Buka App)
  Future<void> rescheduleAllNotifications() async {
    // Ambil semua tugas yang belum selesai
    final activeTasks = await DatabaseHelper.instance.readAllTasks();
    for (var task in activeTasks) {
      if (task.isCompleted == 0 && task.isReminderActive) {
        await _notificationService.scheduleTaskNotification(task);
      }
    }
    debugPrint("Semua notifikasi berhasil dijadwalkan ulang.");
  }
}