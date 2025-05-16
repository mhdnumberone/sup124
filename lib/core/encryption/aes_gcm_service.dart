// lib/core/encryption/aes_gcm_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final aesGcmServiceProvider = Provider((ref) => AesGcmService());

class AesGcmService {
  final AesGcm _aesGcm = AesGcm.with256bits();
  final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 200000, // Increased from 100000 for better security
    bits: 256,
  );

  // Helper method for key derivation - centralized to avoid code duplication
  Future<SecretKey> _deriveKeyFromPassword(String password, List<int> salt) async {
    return await _pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
  }

  Future<String> encryptWithPassword(String plainText, String password) async {
    try {
      // Generate a random salt
      final salt = SecretKeyData.random(length: 16).bytes;
      
      // Derive key using PBKDF2
      final secretKey = await _deriveKeyFromPassword(password, salt);
      
      // Generate a random nonce/IV
      final iv = SecretKeyData.random(length: 12).bytes;
      
      // Convert input to bytes
      final plainBytes = utf8.encode(plainText);
      
      // Encrypt
      final secretBox = await _aesGcm.encrypt(
        plainBytes,
        secretKey: secretKey,
        nonce: iv,
      );
      
      // Combine all components (salt + iv + ciphertext + mac)
      final combined = Uint8List.fromList(
          salt + iv + secretBox.cipherText + secretBox.mac.bytes);
          
      // Encode as base64url for string representation
      return base64UrlEncode(combined);
    } catch (e) {
      // Logged by the calling Notifier
      throw Exception('Encryption failed: ${e.toString()}');
    }
  }

  Future<String> decryptWithPassword(
      String base64CipherText, String password) async {
    try {
      // Decode the base64 input
      final combined = base64Url.decode(base64CipherText);
      
      // Validate minimum length
      if (combined.length < (16 + 12 + 0 + 16)) {
        throw Exception('Invalid encrypted data format: too short.');
      }
      
      // Extract components
      final salt = combined.sublist(0, 16);
      final iv = combined.sublist(16, 16 + 12);
      final cipherText = combined.sublist(16 + 12, combined.length - 16);
      final macBytes = combined.sublist(combined.length - 16);
      final mac = Mac(macBytes);
      
      // Derive key using same approach as encryption
      final secretKey = await _deriveKeyFromPassword(password, salt);
      
      // Create SecretBox with all components
      final secretBox = SecretBox(cipherText, nonce: iv, mac: mac);
      
      // Decrypt
      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      // Convert bytes back to string
      return utf8.decode(decryptedBytes);
    } on SecretBoxAuthenticationError {
      // Authentication failed (wrong password or tampered data)
      throw Exception('Decryption failed: Wrong password or data corrupted.');
    } catch (e) {
      if (e is Exception && e.toString().contains('Authentication failed')) {
        throw Exception('Decryption failed: Wrong password or data corrupted.');
      }
      throw Exception('Decryption failed: ${e.toString()}');
    }
  }

  Future<Uint8List> encryptBytesWithPassword(
      Uint8List plainBytes, String password) async {
    try {
      // Generate a random salt
      final salt = SecretKeyData.random(length: 16).bytes;
      
      // Derive key using PBKDF2
      final secretKey = await _deriveKeyFromPassword(password, salt);
      
      // Generate a random nonce/IV
      final iv = SecretKeyData.random(length: 12).bytes;
      
      // Encrypt
      final secretBox = await _aesGcm.encrypt(
        plainBytes,
        secretKey: secretKey,
        nonce: iv,
      );
      
      // Combine all components (salt + iv + ciphertext + mac)
      final combined = Uint8List.fromList(
          salt + iv + secretBox.cipherText + secretBox.mac.bytes);
          
      return combined;
    } catch (e) {
      throw Exception('Byte encryption failed: ${e.toString()}');
    }
  }

  Future<Uint8List> decryptBytesWithPassword(
      Uint8List encryptedBytes, String password) async {
    try {
      // Validate minimum length
      if (encryptedBytes.length < (16 + 12 + 0 + 16)) {
        throw Exception('Invalid encrypted data format: too short.');
      }
      
      // Extract components
      final salt = encryptedBytes.sublist(0, 16);
      final iv = encryptedBytes.sublist(16, 16 + 12);
      final cipherText =
          encryptedBytes.sublist(16 + 12, encryptedBytes.length - 16);
      final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);
      final mac = Mac(macBytes);
      
      // Derive key using same approach as encryption
      final secretKey = await _deriveKeyFromPassword(password, salt);
      
      // Create SecretBox with all components
      final secretBox = SecretBox(cipherText, nonce: iv, mac: mac);
      
      // Decrypt
      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      return Uint8List.fromList(decryptedBytes);
    } on SecretBoxAuthenticationError {
      throw Exception(
          'Byte decryption failed: Wrong password or data corrupted.');
    } catch (e) {
      if (e is Exception && e.toString().contains('Authentication failed')) {
        throw Exception(
            'Byte decryption failed: Wrong password or data corrupted.');
      }
      throw Exception('Byte decryption failed: ${e.toString()}');
    }
  }
}