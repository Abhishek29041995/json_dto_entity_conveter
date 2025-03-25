import 'dart:convert';
import 'dart:io';

void main() {
  checkDependencies();

  print("Enter JSON file path:");
  String? filePath = stdin.readLineSync()?.trim();

  if (filePath == null || filePath.isEmpty) {
    print("Error: No file path provided.");
    return;
  }

  File file = File(filePath);

  if (!file.existsSync()) {
    print("Error: File not found at $filePath");
    return;
  }

  try {
    String jsonString = file.readAsStringSync().trim();
    jsonString = jsonString.replaceAll(': null', ': ""');
    Map<String, dynamic> jsonData = jsonDecode(jsonString);

    print("Enter module name:");
    String? module = stdin.readLineSync()?.trim();

    print("Enter folder name:");
    String? folderName = stdin.readLineSync()?.trim();

    if (module == null || folderName == null || module.isEmpty || folderName.isEmpty) {
      print("Module name and folder name cannot be empty!");
      return;
    }

    processJson(module, folderName, jsonData);
    
    // Run build_runner after generating files
    print("\nRunning build_runner...");
    Process.runSync('flutter', ['pub', 'run', 'build_runner', 'build', '--delete-conflicting-outputs']);
    print("✅ Build completed!");

  } catch (e) {
    print("Error parsing JSON: $e");
  }
}

void checkDependencies() {
  File pubspecFile = File("pubspec.yaml");
  if (!pubspecFile.existsSync()) {
    print("Error: pubspec.yaml not found! Run this script inside a Flutter project.");
    exit(1);
  }

  List<String> dependencies = [
    "freezed_annotation",
    "json_serializable",
    "build_runner",
    "freezed"
  ];
  List<String> missingDeps = [];

  List<String> lines = pubspecFile.readAsLinesSync();
  for (var dep in dependencies) {
    if (!lines.any((line) => line.trim().startsWith("$dep:"))) {
      missingDeps.add(dep);
    }
  }

  if (missingDeps.isNotEmpty) {
    print("\nThe following dependencies are missing: ${missingDeps.join(', ')}");
    print("Do you want to add them? (y/n)");
    String? response = stdin.readLineSync();
    if (response?.toLowerCase() == 'y') {
      for (var dep in missingDeps) {
        Process.runSync('flutter', ['pub', 'add', dep]);
      }
      print("Dependencies added successfully.");
    } else {
      print("Skipping dependency installation.");
    }
  } else {
    print("All required dependencies are already installed.");
  }
}

void processJson(String module, String folderName, Map<String, dynamic> jsonData) {
  String pascalFolderName = toPascalCase(folderName);
  String infrastructurePath = "lib/infrastructure/$module/$folderName/";
  String domainPath = "lib/domain/$module/$folderName/";

  Directory(infrastructurePath).createSync(recursive: true);
  Directory(domainPath).createSync(recursive: true);

  generateDtoFile(module, folderName, pascalFolderName, jsonData, infrastructurePath, domainPath);
}

void generateDtoFile(
  String module,
  String folderName,
  String pascalFolderName,
  Map<String, dynamic> jsonData,
  String infraPath,
  String domainPath
) {
  String dtoFilePath = "$infraPath${folderName}_dto.dart";
  String entityFilePath = "$domainPath$folderName.dart";

  // Generate child DTOs and entities for nested objects
  List<String> imports = [];
  jsonData.forEach((key, value) {
    if (value is Map) {
      String childName = toPascalCase(key);
      generateDtoFile(module, key, childName, value as Map<String, dynamic>, infraPath, domainPath);
      imports.add("import 'package:test_app/infrastructure/$module/$key/${key}_dto.dart';");
    }
  });

  // Overwrite files if they already exist
  print("Generating DTO: $dtoFilePath...");
  File(dtoFilePath).writeAsStringSync(generateDtoContent(module, folderName, pascalFolderName, jsonData, imports));

  print("Generating Entity: $entityFilePath...");
  File(entityFilePath).writeAsStringSync(generateEntityContent(module, folderName, pascalFolderName, jsonData, imports));

  print("✅ DTO and entity files created successfully!");
}

String generateDtoContent(String module, String folderName, String pascalFolderName, Map<String, dynamic> jsonData, List<String> imports) {
  StringBuffer buffer = StringBuffer();
  buffer.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
  buffer.writeln("import 'package:test_app/domain/$module/$folderName/$folderName.dart';");
  imports.forEach(buffer.writeln);
  buffer.writeln("");
  buffer.writeln("part '${folderName}_dto.freezed.dart';");
  buffer.writeln("part '${folderName}_dto.g.dart';");
  buffer.writeln("");
  buffer.writeln("@freezed");
  buffer.writeln("class ${pascalFolderName}Dto with _\$${pascalFolderName}Dto {");
  buffer.writeln("  factory ${pascalFolderName}Dto({");

  jsonData.forEach((key, value) {
    buffer.writeln("    required ${getDartType(key, value)} $key,");
  });

  buffer.writeln("  }) = _${pascalFolderName}Dto;");
  buffer.writeln("");
  buffer.writeln("  factory ${pascalFolderName}Dto.fromJson(Map<String, dynamic> json) =>");
  buffer.writeln("      _\$${pascalFolderName}DtoFromJson(json);");
  buffer.writeln("");
  buffer.writeln("  $pascalFolderName toDomain() {");
  buffer.writeln("    return $pascalFolderName(");
  
  jsonData.keys.forEach((key) {
    buffer.writeln("      $key: $key,");
  });

  buffer.writeln("    );");
  buffer.writeln("  }");
  buffer.writeln("}");
  return buffer.toString();
}

String generateEntityContent(String module, String folderName, String pascalFolderName, Map<String, dynamic> jsonData, List<String> imports) {
  StringBuffer buffer = StringBuffer();
  buffer.writeln("class $pascalFolderName {");
  imports.forEach(buffer.writeln);
  jsonData.forEach((key, value) {
    buffer.writeln("  final ${getDartType(key, value)} $key;");
  });

  buffer.writeln("");
  buffer.writeln("  $pascalFolderName({");

  jsonData.keys.forEach((key) {
    buffer.writeln("    required this.$key,");
  });

  buffer.writeln("  });");
  buffer.writeln("}");
  return buffer.toString();
}

String toPascalCase(String text) {
  return text.split('_').map((e) => e[0].toUpperCase() + e.substring(1)).join();
}

String getDartType(String key, dynamic value) {
  if (value is int) return "int";
  if (value is double) return "double";
  if (value is bool) return "bool";
  if (value is List) return "List<${getDartType(key, value.first)}>";
  if (value is Map) return "${toPascalCase(key)}Dto"; // Create DTO for nested object
  return "String";
}
