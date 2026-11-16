namespace AwsEmulatorSharp.Emulator.Install;

public class InstallPlan
{
    public InstallPlan(string instanceId, string mediaBucketName, IReadOnlyList<InstallStep> steps, string reportServerUrl, string portalUrl)
    {
        InstanceId = instanceId;
        MediaBucketName = mediaBucketName;
        Steps = steps;
        ReportServerUrl = reportServerUrl;
        PortalUrl = portalUrl;
    }

    public string InstanceId { get; }

    public string MediaBucketName { get; }

    public IReadOnlyList<InstallStep> Steps { get; }

    public string ReportServerUrl { get; }

    public string PortalUrl { get; }
}
