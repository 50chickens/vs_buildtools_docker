namespace AwsEmulatorSharp.Emulator.Install;

public class InstallStep
{
    public InstallStep(string name, string installerKey, string installerUrl, string commandLine)
    {
        Name = name;
        InstallerKey = installerKey;
        InstallerUrl = installerUrl;
        CommandLine = commandLine;
    }

    public string Name { get; }

    public string InstallerKey { get; }

    public string InstallerUrl { get; }

    public string CommandLine { get; }
}
