import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String id;
  final String userId;
  final String plan; // basic, medium, premium
  final int amountPaid; // in INR
  final String razorpayPaymentId;
  final String razorpayOrderId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final DateTime createdAt;

  const SubscriptionModel({
    required this.id,
    required this.userId,
    required this.plan,
    required this.amountPaid,
    required this.razorpayPaymentId,
    required this.razorpayOrderId,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    required this.createdAt,
  });

  factory SubscriptionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SubscriptionModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      plan: d['plan'] ?? 'basic',
      amountPaid: d['amountPaid'] ?? 0,
      razorpayPaymentId: d['razorpayPaymentId'] ?? '',
      razorpayOrderId: d['razorpayOrderId'] ?? '',
      startDate: (d['startDate'] as Timestamp).toDate(),
      endDate: (d['endDate'] as Timestamp).toDate(),
      isActive: d['isActive'] ?? true,
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'plan': plan,
        'amountPaid': amountPaid,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpayOrderId': razorpayOrderId,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  bool get isExpired => endDate.isBefore(DateTime.now());
  int get daysRemaining => endDate.difference(DateTime.now()).inDays;
}
