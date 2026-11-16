using System.Globalization;
using System.Text;
using AwsEmulatorSharp.Emulator.Ec2;
using AwsEmulatorSharp.Emulator.Ec2.Lifecycle;
using AwsEmulatorSharp.Emulator.Host;
using AwsEmulatorSharp.Emulator.Install;
using AwsEmulatorSharp.Emulator.S3;
using AwsEmulatorSharp.Emulator.Tests.Identity;
using FiftyChickens.Library.Testing;
using NUnit.Framework;

namespace AwsEmulatorSharp.Emulator.Tests.Install;

[TimedTestFixture(1)]
public class InstallPlanGeneratorTests
{
    private const string MediaFileName = "sql-server-setup.exe";
    private const string OlderMediaFileName = "sql-server-setup-2025.exe";
    private const string ReportingInstallerFileName = "PowerBIReportServer.exe";
    private const string DatabaseEngineStepName = "database-engine";
    private const string ReportServerStepName = "report-server";
    private const string MediaContentText = "installer-media";
    private const string InstanceId = "i-0123456789abcdef0";
    private const string ReservationId = "r-0123456789abcdef0";
    private const string ImageId = "ami-0123456789abcdef0";
    private const string InstanceType = "m5.large";
    private const string ContainerId = "container-1";
    private const string PrivateIpAddress = "10.0.0.4";
    private const string StateName = "running";
    private const string ConsoleOutput = "";
    private const string SigningDate = "20261115";
    private const string SigningTimestamp = "20261115T104209Z";
    private const string CredentialFormat = "{0}/{1}/{2}/s3/aws4_request";
    private const string PresignedUrlFormat = "{0}/{1}?X-Amz-Algorithm=AWS4-HMAC-SHA256";
    private const string EndpointFormat = "http://{0}:{1}/";
    private const string ExpectedDatabaseEngineCommandLineFormat = "\"{0}\\{1}\" /Q /ACTION=Install /FEATURES=SQLENGINE,FULLTEXT,IS,Conn,SDK /IACCEPTSQLSERVERLICENSETERMS";
    private const string ExpectedReportServerCommandLineFormat = "\"{0}\\{1}\" /quiet /ACTION=INSTALL /INSTANCENAME=SSRS /EDITION=Developer /IAcceptLicenseTerms";
    private const string ReportServerInstanceName = "SSRS";
    private const string UrlFormat = "http://{0}{1}";
    private const string SignatureQueryName = "X-Amz-Signature=";
    private const string ExpectedSignature = "cc32958840dae4d681c3e35b12c157c5f44805ee22120cf5d272ef6c7abcd8ff";
    private const int StateCode = 16;
    private const int BootCount = 1;
    private const bool UserDataFailed = false;

    private static readonly DateTimeOffset _signingTime = new(2026, 11, 15, 10, 42, 9, TimeSpan.Zero);

    private HostConfiguration _hostConfiguration;
    private Ec2Configuration _ec2Configuration;
    private InstallConfiguration _configuration;
    private Ec2Instance _instance;
    private InstallPlanGenerator _generator;
    private string _mediaKey;
    private string _reportingInstallerKey;

    [SetUp]
    public void SetUp()
    {
        _hostConfiguration = new HostConfigurationReader().Read();
        _ec2Configuration = new Ec2ConfigurationReader().Read();
        _configuration = new InstallConfigurationReader().Read();
        _mediaKey = _configuration.MediaKeyPrefix + MediaFileName;
        _reportingInstallerKey = _configuration.ReportingMediaKeyPrefix + ReportingInstallerFileName;
        var olderMediaKey = _configuration.MediaKeyPrefix + OlderMediaFileName;
        var objectStore = new ObjectStore();
        objectStore.PutObject(_configuration.MediaBucketName, olderMediaKey, Encoding.UTF8.GetBytes(MediaContentText));
        objectStore.PutObject(_configuration.MediaBucketName, _mediaKey, Encoding.UTF8.GetBytes(MediaContentText));
        objectStore.PutObject(_configuration.MediaBucketName, _reportingInstallerKey, Encoding.UTF8.GetBytes(MediaContentText));
        var timeProvider = new FixedTimeProvider(_signingTime);
        var mediaUrlMinter = new MediaUrlMinter(_hostConfiguration, _ec2Configuration, timeProvider);

        _generator = new InstallPlanGenerator(objectStore, mediaUrlMinter, _configuration);
        _instance = new Ec2Instance(InstanceId, ReservationId, ImageId, InstanceType, ContainerId, PrivateIpAddress, StateName, StateCode, BootCount, ConsoleOutput, UserDataFailed);
    }

    [Test]
    public void Test_That_The_Plan_For_An_Instance_Is_For_That_Instance()
    {
        var plan = _generator.For(_instance);

        Assert.That(plan.InstanceId, Is.EqualTo(_instance.InstanceId));
    }

    [Test]
    public void Test_That_The_Plan_Carries_The_Database_Engine_Step_Then_The_Report_Server_Step()
    {
        var plan = _generator.For(_instance);
        var stepNames = plan.Steps.Select(step => step.Name).ToList();
        var expectedStepNames = new List<string> { DatabaseEngineStepName, ReportServerStepName };

        Assert.That(stepNames, Is.EqualTo(expectedStepNames));
    }

    [Test]
    public void Test_That_The_Database_Engine_Step_Names_The_Newest_Media_Object_The_Object_Store_Holds()
    {
        var plan = _generator.For(_instance);
        var databaseEngineStep = plan.Steps.Single(step => step.Name.Equals(DatabaseEngineStepName));

        Assert.That(plan.MediaBucketName, Is.EqualTo(_configuration.MediaBucketName));
        Assert.That(databaseEngineStep.InstallerKey, Is.EqualTo(_mediaKey));
    }

    [Test]
    public void Test_That_The_Presigned_Installer_Url_Addresses_The_Media_Object_From_The_Container_Endpoint()
    {
        var plan = _generator.For(_instance);
        var databaseEngineStep = plan.Steps.Single(step => step.Name.Equals(DatabaseEngineStepName));
        var endpoint = string.Format(CultureInfo.InvariantCulture, EndpointFormat, _hostConfiguration.ContainerHostName, _hostConfiguration.ListenerPort);
        var presignedPath = string.Format(CultureInfo.InvariantCulture, PresignedUrlFormat, _configuration.MediaBucketName, _mediaKey);

        Assert.That(databaseEngineStep.InstallerUrl, Does.Contain(endpoint));
        Assert.That(databaseEngineStep.InstallerUrl, Does.Contain(presignedPath));
    }

    [Test]
    public void Test_That_The_Presigned_Installer_Url_Is_Signed_With_The_Emulator_Credential()
    {
        var plan = _generator.For(_instance);
        var databaseEngineStep = plan.Steps.Single(step => step.Name.Equals(DatabaseEngineStepName));
        var credential = string.Format(CultureInfo.InvariantCulture, CredentialFormat, _hostConfiguration.Credentials.AccessKeyId, SigningDate, _ec2Configuration.Region.Name);

        Assert.That(databaseEngineStep.InstallerUrl, Does.Contain(Uri.EscapeDataString(credential)));
        Assert.That(databaseEngineStep.InstallerUrl, Does.Contain(SigningTimestamp));
        Assert.That(databaseEngineStep.InstallerUrl, Does.Contain(SignatureQueryName + ExpectedSignature));
    }

    [Test]
    public void Test_That_The_Database_Engine_Step_Carries_An_Unattended_Setup_Command_Line_With_The_Database_Engine_Feature_Set()
    {
        var plan = _generator.For(_instance);
        var databaseEngineStep = plan.Steps.Single(step => step.Name.Equals(DatabaseEngineStepName));
        var expectedCommandLine = string.Format(CultureInfo.InvariantCulture, ExpectedDatabaseEngineCommandLineFormat, _configuration.MediaFolderPath, MediaFileName);

        Assert.That(databaseEngineStep.CommandLine, Is.EqualTo(expectedCommandLine));
    }

    [Test]
    public void Test_That_The_Report_Server_Step_Names_The_Reporting_Installer()
    {
        var plan = _generator.For(_instance);
        var reportServerStep = plan.Steps.OfType<ReportServerInstallStep>().Single();

        Assert.That(reportServerStep.InstallerKey, Is.EqualTo(_reportingInstallerKey));
    }

    [Test]
    public void Test_That_The_Report_Server_Step_Carries_An_Unattended_Report_Server_Command_Line()
    {
        var plan = _generator.For(_instance);
        var reportServerStep = plan.Steps.OfType<ReportServerInstallStep>().Single();
        var expectedCommandLine = string.Format(CultureInfo.InvariantCulture, ExpectedReportServerCommandLineFormat, _configuration.MediaFolderPath, ReportingInstallerFileName);

        Assert.That(reportServerStep.CommandLine, Is.EqualTo(expectedCommandLine));
    }

    [Test]
    public void Test_That_The_Report_Server_Step_Names_The_Report_Server_Database_It_Configures()
    {
        var plan = _generator.For(_instance);
        var reportServerStep = plan.Steps.OfType<ReportServerInstallStep>().Single();

        Assert.That(reportServerStep.DatabaseName, Is.EqualTo(_configuration.ReportServerDatabaseName));
    }

    [Test]
    public void Test_That_The_Report_Server_Step_Names_The_Instance_Whose_Database_It_Configures()
    {
        var plan = _generator.For(_instance);
        var reportServerStep = plan.Steps.OfType<ReportServerInstallStep>().Single();

        Assert.That(reportServerStep.InstanceName, Is.EqualTo(ReportServerInstanceName));
    }

    [Test]
    public void Test_That_The_Plan_Names_The_Report_Server_Url_The_Running_Container_Answers_On()
    {
        var plan = _generator.For(_instance);
        var expectedReportServerUrl = string.Format(CultureInfo.InvariantCulture, UrlFormat, _instance.PrivateIpAddress, _configuration.ReportServerUrlPath);

        Assert.That(plan.ReportServerUrl, Is.EqualTo(expectedReportServerUrl));
    }

    [Test]
    public void Test_That_The_Plan_Names_The_Portal_Url_The_Running_Container_Answers_On()
    {
        var plan = _generator.For(_instance);
        var expectedPortalUrl = string.Format(CultureInfo.InvariantCulture, UrlFormat, _instance.PrivateIpAddress, _configuration.PortalUrlPath);

        Assert.That(plan.PortalUrl, Is.EqualTo(expectedPortalUrl));
    }
}
