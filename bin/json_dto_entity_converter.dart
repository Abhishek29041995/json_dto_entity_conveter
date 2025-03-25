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
    // Replace null values with empty strings for compatibility
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
  String infrastructurePath = "lib/infrastructure/$module/$folderName/";
  String domainPath = "lib/domain/$module/$folderName/";

  Directory(infrastructurePath).createSync(recursive: true);
  Directory(domainPath).createSync(recursive: true);

  generateDtoFile(module, folderName, jsonData, infrastructurePath, domainPath);
}

void generateDtoFile(
  String module,
  String folderName,
  Map<String, dynamic> jsonData,
  String infraPath,
  String domainPath
) {
  String dtoFilePath = "$infraPath${folderName}_dto.dart";
  String entityFilePath = "$domainPath$folderName.dart";

  if (File(dtoFilePath).existsSync()) {
    print("DTO file '$dtoFilePath' already exists. Enter a new name:");
    String? newFolderName = stdin.readLineSync()?.trim();
    if (newFolderName == null || newFolderName.isEmpty) {
      print("Invalid name. Exiting.");
      return;
    }
    folderName = newFolderName;
    infraPath = "lib/infrastructure/$module/$folderName/";
    domainPath = "lib/domain/$module/$folderName/";
    dtoFilePath = "$infraPath${folderName}_dto.dart";
    entityFilePath = "$domainPath$folderName.dart";

    Directory(infraPath).createSync(recursive: true);
    Directory(domainPath).createSync(recursive: true);
  }

  String dtoContent = generateDtoContent(folderName, jsonData);
  File(dtoFilePath).writeAsStringSync(dtoContent);

  String entityContent = generateEntityContent(folderName, jsonData);
  File(entityFilePath).writeAsStringSync(entityContent);

  print("✅ DTO and entity files created successfully!");
}

String generateDtoContent(String folderName, Map<String, dynamic> jsonData) {
  StringBuffer buffer = StringBuffer();
  buffer.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
  buffer.writeln("import '../../domain/$folderName/$folderName.dart';");
  buffer.writeln("");
  buffer.writeln("part '${folderName}_dto.freezed.dart';");
  buffer.writeln("part '${folderName}_dto.g.dart';");
  buffer.writeln("");
  buffer.writeln("@freezed");
  buffer.writeln("class ${capitalize(folderName)}Dto with _\$${capitalize(folderName)}Dto {");
  buffer.writeln("  factory ${capitalize(folderName)}Dto({");

  jsonData.forEach((key, value) {
    buffer.writeln("    required ${getDartType(value)} $key,");
  });

  buffer.writeln("  }) = _${capitalize(folderName)}Dto;");
  buffer.writeln("");
  buffer.writeln("  factory ${capitalize(folderName)}Dto.fromJson(Map<String, dynamic> json) =>");
  buffer.writeln("      _\$${capitalize(folderName)}DtoFromJson(json);");
  buffer.writeln("");
  buffer.writeln("  ${capitalize(folderName)} toDomain() {");
  buffer.writeln("    return ${capitalize(folderName)}(");
  
  jsonData.keys.forEach((key) {
    buffer.writeln("      $key: $key,");
  });

  buffer.writeln("    );");
  buffer.writeln("  }");
  buffer.writeln("}");
  return buffer.toString();
}

String generateEntityContent(String folderName, Map<String, dynamic> jsonData) {
  StringBuffer buffer = StringBuffer();
  buffer.writeln("class ${capitalize(folderName)} {");
  jsonData.forEach((key, value) {
    buffer.writeln("  final ${getDartType(value)} $key;");
  });

  buffer.writeln("");
  buffer.writeln("  ${capitalize(folderName)}({");

  jsonData.keys.forEach((key) {
    buffer.writeln("    required this.$key,");
  });

  buffer.writeln("  });");
  buffer.writeln("}");
  return buffer.toString();
}

String capitalize(String text) {
  return text.isNotEmpty ? text[0].toUpperCase() + text.substring(1) : text;
}

String getDartType(dynamic value) {
  if (value is int) return "int";
  if (value is double) return "double";
  if (value is bool) return "bool";
  if (value is List) return "List<${getDartType(value.first)}>";
  if (value is Map) return "Map<String, dynamic>";
  return "String";
}
