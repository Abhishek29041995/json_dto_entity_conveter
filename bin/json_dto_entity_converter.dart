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

    if (module == null || module.isEmpty) {
      print("Module name is mandatory!");
      return;
    }

    print("Do you want to maintain a parent folder? (y/n)");
    String? maintainParentFolder = stdin.readLineSync()?.trim().toLowerCase();
    bool useParentFolder = maintainParentFolder == 'y';
    String folderName = '';

    if (useParentFolder) {
      print("Enter folder name:");
      folderName = stdin.readLineSync()?.trim() ?? '';

      if (folderName.isEmpty) {
        print("Folder name cannot be empty!");
        return;
      }
    }

    processJson(module, folderName, jsonData, useParentFolder);
    
    // Run build_runner after generating files
    runBuildRunner();

  } catch (e) {
    print("Error parsing JSON: $e");
  }
}

void runBuildRunner() {
  print("\nRunning build_runner...");

  ProcessResult result = Process.runSync(
    'flutter',
    ['pub', 'run', 'build_runner', 'watch', '--delete-conflicting-outputs'],
    runInShell: true,
  );

  if (result.exitCode != 0) {
    print("❌ Build Runner failed with errors:\n${result.stderr}");
  } else {
    print("✅ Build completed successfully!");
  }
}


void checkDependencies() {
  File pubspecFile = File("pubspec.yaml");
  if (!pubspecFile.existsSync()) {
    print("Error: pubspec.yaml not found! Run this script inside a Flutter project.");
    exit(1);
  }

  // Define dependencies and their versions
  Map<String, String> dependencies = {
    "freezed_annotation": "^3.0.0",
  };

  Map<String, String> devDependencies = {
    "freezed": "^3.0.4",
    "build_runner": "^2.4.15",
    "json_serializable": "^6.9.4",
  };

  List<String> missingDeps = [];
  List<String> missingDevDeps = [];

  List<String> lines = pubspecFile.readAsLinesSync();

  // Check for missing dependencies
  dependencies.forEach((dep, version) {
    if (!lines.any((line) => line.trim().startsWith("$dep:"))) {
      missingDeps.add("$dep: $version");
    }
  });

  // Check for missing dev_dependencies
  devDependencies.forEach((dep, version) {
    if (!lines.any((line) => line.trim().startsWith("$dep:"))) {
      missingDevDeps.add("$dep: $version");
    }
  });

  if (missingDeps.isNotEmpty || missingDevDeps.isNotEmpty) {
    print("\nThe following dependencies are missing:");
    if (missingDeps.isNotEmpty) {
      print("Dependencies: ${missingDeps.join(', ')}");
    }
    if (missingDevDeps.isNotEmpty) {
      print("Dev Dependencies: ${missingDevDeps.join(', ')}");
    }

    print("\nDo you want to add them? (y/n)");
    String? response = stdin.readLineSync();
    if (response?.toLowerCase() == 'y') {
      // Add missing dependencies
      if (missingDeps.isNotEmpty) {
        for (var dep in missingDeps) {
          Process.runSync('flutter', ['pub', 'add', dep.split(':').first, '--sdk', 'flutter']);
        }
      }

      // Add missing dev_dependencies
      if (missingDevDeps.isNotEmpty) {
        for (var devDep in missingDevDeps) {
          Process.runSync('flutter', ['pub', 'add', devDep.split(':').first, '--dev']);
        }
      }

      print("Dependencies added successfully.");
    } else {
      print("Skipping dependency installation.");
    }
  } else {
    print("All required dependencies are already installed.");
  }
}


void processJson(String module, String folderName, Map<String, dynamic> jsonData, bool useParentFolder) {
  String pascalFolderName = toPascalCase(folderName.isEmpty ? module : folderName);
  String infrastructurePath = "lib/infrastructure/$module/${useParentFolder ? '$folderName/' : ''}";
  String domainPath = "lib/domain/$module/${useParentFolder ? '$folderName/' : ''}";

  Directory(infrastructurePath).createSync(recursive: true);
  Directory(domainPath).createSync(recursive: true);

  generateDtoFile(module, folderName, pascalFolderName, jsonData, infrastructurePath, domainPath, useParentFolder);
}

void generateDtoFile(
  String module,
  String folderName,
  String pascalFolderName,
  Map<String, dynamic> jsonData,
  String infraPath,
  String domainPath,
  bool useParentFolder
) {
  String dtoFilePath = "$infraPath${folderName.isEmpty ? module : folderName}_dto.dart";
  String entityFilePath = "$domainPath${folderName.isEmpty ? module : folderName}.dart";

  List<String> imports = [];
  jsonData.forEach((key, value) {
    if (value is List && value.isNotEmpty && value.first is Map) {
      String childName = toPascalCase(key);
      generateDtoFile(module, key, childName, value.first, infraPath, domainPath, useParentFolder);
      imports.add("import 'package:test_app/infrastructure/$module/${useParentFolder ? '$folderName/' : ''}${key}_dto.dart';");
    } else if (value is Map) {
      String childName = toPascalCase(key);
      generateDtoFile(module, key, childName, value as Map<String, dynamic>, infraPath, domainPath, useParentFolder);
      imports.add("import 'package:test_app/infrastructure/$module/${useParentFolder ? '$folderName/' : ''}${key}_dto.dart';");
    }
  });

  print("Generating DTO: $dtoFilePath...");
  File(dtoFilePath).writeAsStringSync(generateDtoContent(module, folderName, pascalFolderName, jsonData, imports, useParentFolder));

  print("Generating Entity: $entityFilePath...");
  File(entityFilePath).writeAsStringSync(generateEntityContent(module, folderName, pascalFolderName, jsonData, imports, useParentFolder));

  print("✅ DTO and entity files created successfully!");
}


String generateDtoContent(String module, String folderName, String pascalFolderName, Map<String, dynamic> jsonData, List<String> imports, bool useParentFolder) {
  StringBuffer buffer = StringBuffer();
  buffer.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");

  // If folderName is empty, use module name as the folder name
  String actualFolderName = folderName.isEmpty ? module : folderName;

  // Ensure correct domain import without an extra folder when no parent folder is used
  if (useParentFolder) {
    buffer.writeln("import 'package:test_app/domain/$module/$actualFolderName/$actualFolderName.dart';");
  } else {
    buffer.writeln("import 'package:test_app/domain/$module/$actualFolderName.dart';");
  }

  // Ensure DTO imports from `infrastructure`
  imports = imports.map((import) {
    return import.replaceAll("package:test_app/domain/", "package:test_app/infrastructure/")
                 .replaceAll(".dart';", "_dto.dart';") // Ensure correct DTO import
                 .replaceAll("_dto_dto.dart", "_dto.dart"); // Fix duplicate `_dto_dto`
  }).toList();

  imports.forEach(buffer.writeln);

  buffer.writeln("");
  buffer.writeln("part '${actualFolderName}_dto.freezed.dart';");
  buffer.writeln("part '${actualFolderName}_dto.g.dart';");
  buffer.writeln("");
  buffer.writeln("@freezed");
  buffer.writeln("class ${pascalFolderName}DTO with _\$${pascalFolderName}DTO {");
  buffer.writeln("  const ${pascalFolderName}DTO._();");
  buffer.writeln("  factory ${pascalFolderName}DTO({");

  jsonData.forEach((key, value) {
    if (value is Map) {
      buffer.writeln("    @Default(${toPascalCase(key)}DTO.empty)");
    }
    buffer.writeln("    @JsonKey(name: '$key') required ${getDartType(key, value, isDto: true)} $key,");
  });

  buffer.writeln("  }) = _${pascalFolderName}DTO;");
  buffer.writeln("");
  buffer.writeln("  factory ${pascalFolderName}DTO.fromJson(Map<String, dynamic> json) =>");
  buffer.writeln("      _\$${pascalFolderName}DTOFromJson(json);");
  buffer.writeln("");
  buffer.writeln("  static const empty = ${pascalFolderName}DTO(");
  jsonData.forEach((key, value) {
    buffer.writeln("    $key: ${getDefaultValue(key, value)},");
  });
  buffer.writeln("  );");
  buffer.writeln("");
  buffer.writeln("  ${pascalFolderName} toDomain() => ${pascalFolderName}(");
  jsonData.forEach((key, value) {
    if (value is List) {
      buffer.writeln("    $key: $key.map((e) => e.toDomain()).toList(),");
    } else if (value is Map) {
      buffer.writeln("    $key: $key.toDomain(),");
    } else {
      buffer.writeln("    $key: $key,");
    }
  });
  buffer.writeln("  );");
  buffer.writeln("}");
  return buffer.toString();
}

String generateEntityContent(String module, String folderName, String pascalFolderName, Map<String, dynamic> jsonData, List<String> imports, bool useParentFolder) {
  StringBuffer buffer = StringBuffer();
  buffer.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");

  // If folderName is empty, use module name as the folder name
  String actualFolderName = folderName.isEmpty ? module : folderName;

  // Ensure entity imports from `domain`, not `infrastructure`
  imports = imports.map((import) {
    return import.replaceAll("package:test_app/infrastructure/", "package:test_app/domain/")
                 .replaceAll("_dto.dart';", ".dart';"); // Convert DTO imports to entity imports
  }).toList();

  imports.forEach(buffer.writeln);

  buffer.writeln("");
  buffer.writeln("part '${actualFolderName}.freezed.dart';"); // ✅ Removed `.g.dart`
  buffer.writeln("");
  buffer.writeln("@freezed");
  buffer.writeln("class $pascalFolderName with _\$$pascalFolderName {");
  buffer.writeln("  const $pascalFolderName._();");
  
  // ✅ Add `const` before factory constructor
  buffer.writeln("  const factory $pascalFolderName({");

  jsonData.forEach((key, value) {
    buffer.writeln("    required ${getDartType(key, value, isDto: false)} $key,");
  });

  buffer.writeln("  }) = _$pascalFolderName;");
  buffer.writeln("");

  // ✅ Keep `empty()` without `const`
  buffer.writeln("  factory $pascalFolderName.empty() => $pascalFolderName(");
  jsonData.forEach((key, value) {
    if (value is List && key.toLowerCase().contains("items")) {
      buffer.writeln("    $key: <${toPascalCase(key)}>[],");
    } else if (value is Map && key.toLowerCase().contains("price")) {
      buffer.writeln("    $key: ${toPascalCase(key)}.empty(),");
    } else {
      buffer.writeln("    $key: ${getDefaultValue(key, value)},");
    }
  });
  buffer.writeln("  );");
  buffer.writeln("}");
  return buffer.toString();
}


String getDefaultValue(String key, dynamic value) {
  if (value is List) {
    return isPrimitiveList(value) ? "<String>[]" : "<${toPascalCase(key)}DTO>[]";
  }
  if (value is Map) return "${toPascalCase(key)}DTO.empty";
  if (value is int) return "0";
  if (value is double) return "0.0";
  if (value is bool) return "false";
  return "''";
}

String getDartType(String key, dynamic value, {required bool isDto}) {
  if (value is int) return "int";
  if (value is double) return "double";
  if (value is bool) return "bool";
  if (value is List) {
    return isPrimitiveList(value) ? "List<String>" : "List<${toPascalCase(key)}${isDto ? 'DTO' : ''}>";
  }
  if (value is Map) return "${toPascalCase(key)}${isDto ? 'DTO' : ''}";
  return "String";
}

bool isPrimitiveList(List<dynamic> value) {
  return value.isEmpty || value.every((item) => item is String || item is int || item is double || item is bool);
}

String toPascalCase(String text) {
  return text
      .split(RegExp(r'[_\s-]')) 
      .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
      .join();
}
