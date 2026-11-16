namespace AwsEmulatorSharp.Emulator.Install;

public class ReportServerInstallStep : InstallStep
{
    public ReportServerInstallStep(string name, string installerKey, string installerUrl, string commandLine, string instanceName, string databaseName)
        : base(name, installerKey, installerUrl, commandLine)
    {
        InstanceName = instanceName;
        DatabaseName = databaseName;
    }

    public string InstanceName { get; }

    public string DatabaseName { get; }
}
