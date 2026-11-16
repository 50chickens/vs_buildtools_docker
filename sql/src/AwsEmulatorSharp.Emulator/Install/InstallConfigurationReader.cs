using System.Text.Json;

namespace AwsEmulatorSharp.Emulator.Install;

public class InstallConfigurationReader
{
    private const string ConfigurationFolderName = "config";
    private const string ConfigurationFileName = "install.json";

    private static readonly JsonSerializerOptions _serializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public InstallConfiguration Read()
    {
        var path = Path.Combine(AppContext.BaseDirectory, ConfigurationFolderName, ConfigurationFileName);
        var json = File.ReadAllText(path);
        var configuration = JsonSerializer.Deserialize<InstallConfiguration>(json, _serializerOptions);

        return configuration!;
    }
}
