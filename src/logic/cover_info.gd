class_name CoverInfo
extends RefCounted

enum Level { NONE, HALF, FULL }

var level: Level = Level.NONE
var profile: Array[Enums.SlotType] = []
var object: Part = null  # the covering blocker (terrain or destructible), or null if no cover
