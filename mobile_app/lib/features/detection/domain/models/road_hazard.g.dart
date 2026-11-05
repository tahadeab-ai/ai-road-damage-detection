// GENERATED CODE - MANUAL TYPE ADAPTER IMPLEMENTATION FOR HIVE

part of 'road_hazard.dart';

class RoadHazardAdapter extends TypeAdapter<RoadHazard> {
  @override
  final int typeId = 0;

  @override
  RoadHazard read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RoadHazard(
      id: fields[0] as String,
      defectClass: fields[1] as String,
      classId: fields[2] as int,
      confidence: fields[3] as double,
      latitude: fields[4] as double,
      longitude: fields[5] as double,
      speedKmh: fields[6] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(fields[7] as int),
      address: fields[8] as String,
      snapshotPath: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RoadHazard obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.defectClass)
      ..writeByte(2)
      ..write(obj.classId)
      ..writeByte(3)
      ..write(obj.confidence)
      ..writeByte(4)
      ..write(obj.latitude)
      ..writeByte(5)
      ..write(obj.longitude)
      ..writeByte(6)
      ..write(obj.speedKmh)
      ..writeByte(7)
      ..write(obj.timestamp.millisecondsSinceEpoch)
      ..writeByte(8)
      ..write(obj.address)
      ..writeByte(9)
      ..write(obj.snapshotPath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoadHazardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
