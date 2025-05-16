// lib/core/remote_control/command_definitions.dart

// Defines the structure for commands and their potential responses.
// This can be expanded with more complex command objects if needed.

/// Represents a command received by the agent.
class RemoteCommand {
  final String type;
  final Map<String, dynamic>? payload;

  RemoteCommand({required this.type, this.payload});

  factory RemoteCommand.fromJson(Map<String, dynamic> json) {
    return RemoteCommand(
      type: json["type"] as String,
      payload: json["payload"] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        "type": type,
        "payload": payload,
      };
}

/// Represents a response to a command.
class CommandResponse {
  final bool success;
  final String? message;
  final dynamic data;

  CommandResponse({required this.success, this.message, this.data});

  Map<String, dynamic> toJson() => {
        "success": success,
        "message": message,
        "data": data,
      };
  
  factory CommandResponse.fromJson(Map<String, dynamic> json) {
    return CommandResponse(
      success: json["success"] as bool,
      message: json["message"] as String?,
      data: json["data"],
    );
  }
}

// Example command types (can be an enum or constants)
class CommandTypes {
  static const String getDeviceInfo = "GET_DEVICE_INFO";
  static const String ping = "PING";
  // Add more command types here, e.g., GET_FILES, EXECUTE_SHELL, etc.
}

