using System.Globalization;
using AwsEmulatorSharp.Emulator.Ec2.Lifecycle;
using AwsEmulatorSharp.Emulator.S3;

namespace AwsEmulatorSharp.Emulator.Install;

public class InstallPlanGenerator
{
    private const string ObjectKeySeparator = "/";
    private const string SetupQuietSwitch = "/Q";
    private const string ReportServerQuietSwitch = "/quiet";
    private const string DatabaseEngineFeatures = "SQLENGINE,FULLTEXT,IS,Conn,SDK";
    private const string ReportServerInstanceName = "SSRS";
    private const string DatabaseEngineStepName = "database-engine";
    private const string ReportServerStepName = "report-server";
    private const string DatabaseEngineCommandLineFormat = "\"{0}\\{1}\" {2} /ACTION=Install /FEATURES={3} /IACCEPTSQLSERVERLICENSETERMS";
    private const string ReportServerCommandLineFormat = "\"{0}\\{1}\" {2} /ACTION=INSTALL /INSTANCENAME={3} /EDITION={4} /IAcceptLicenseTerms";
    private const string UrlFormat = "http://{0}{1}";

    private readonly IObjectStore _objectStore;
    private readonly MediaUrlMinter _mediaUrlMinter;
    private readonly InstallConfiguration _configuration;

    public InstallPlanGenerator(IObjectStore objectStore, MediaUrlMinter mediaUrlMinter, InstallConfiguration configuration)
    {
        _objectStore = objectStore;
        _mediaUrlMinter = mediaUrlMinter;
        _configuration = configuration;
    }

    public InstallPlan For(Ec2Instance instance)
    {
        var steps = new List<InstallStep> { ToDatabaseEngineStep(), ToReportServerStep() };
        var reportServerUrl = ToUrl(instance, _configuration.ReportServerUrlPath);
        var portalUrl = ToUrl(instance, _configuration.PortalUrlPath);

        return new InstallPlan(instance.InstanceId, _configuration.MediaBucketName, steps, reportServerUrl, portalUrl);
    }

    private InstallStep ToDatabaseEngineStep()
    {
        var installerKey = FindInstallerKey(_configuration.MediaKeyPrefix);
        var installerFileName = installerKey.Split(ObjectKeySeparator).Last();
        var installerUrl = _mediaUrlMinter.For(_configuration.MediaBucketName, installerKey);
        var commandLine = string.Format(CultureInfo.InvariantCulture, DatabaseEngineCommandLineFormat, _configuration.MediaFolderPath, installerFileName, SetupQuietSwitch, DatabaseEngineFeatures);

        return new InstallStep(DatabaseEngineStepName, installerKey, installerUrl, commandLine);
    }

    private ReportServerInstallStep ToReportServerStep()
    {
        var installerKey = FindInstallerKey(_configuration.ReportingMediaKeyPrefix);
        var installerFileName = installerKey.Split(ObjectKeySeparator).Last();
        var installerUrl = _mediaUrlMinter.For(_configuration.MediaBucketName, installerKey);
        var commandLine = string.Format(CultureInfo.InvariantCulture, ReportServerCommandLineFormat, _configuration.MediaFolderPath, installerFileName, ReportServerQuietSwitch, ReportServerInstanceName, _configuration.ReportServerEdition);

        return new ReportServerInstallStep(ReportServerStepName, installerKey, installerUrl, commandLine, ReportServerInstanceName, _configuration.ReportServerDatabaseName);
    }

    private string ToUrl(Ec2Instance instance, string path)
    {
        var url = string.Format(CultureInfo.InvariantCulture, UrlFormat, instance.PrivateIpAddress, path);

        return url;
    }

    private string FindInstallerKey(string mediaKeyPrefix)
    {
        var mediaObjects = _objectStore.FindObjects(_configuration.MediaBucketName, mediaKeyPrefix);

        return mediaObjects.Last().Key;
    }
}
