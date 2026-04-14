using UndertaleModLib;
using UndertaleModLib.Models;
var data = UndertaleIO.Read(new FileStream(args[0], FileMode.Open, FileAccess.Read));
var player = data.GameObjects.ByName("objPlayer");
Console.WriteLine($"objPlayer persistent = {player?.Persistent}");
var world = data.GameObjects.ByName("objWorld");
Console.WriteLine($"objWorld persistent = {world?.Persistent}");

// Check all rooms for whether objPlayer is placed in room editor
foreach (var room in data.Rooms) {
    foreach (var inst in room.GameObjects) {
        if (inst.ObjectDefinition?.Name?.Content == "objPlayer") {
            Console.WriteLine($"objPlayer found in room: {room.Name.Content} at ({inst.X}, {inst.Y})");
        }
    }
}
