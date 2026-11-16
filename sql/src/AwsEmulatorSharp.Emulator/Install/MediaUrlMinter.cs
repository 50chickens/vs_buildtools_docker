using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using AwsEmulatorSharp.Emulator.Ec2;
using AwsEmulatorSharp.Emulator.Host;

namespace AwsEmulatorSharp.Emulator.Install;

public class MediaUrlMinter
{
    private const string Algorithm = "AWS4-HMAC-SHA256";
    private const string ServiceName = "s3";
    private const string Terminator = "aws4_request";
    private const string SigningKeyPrefix = "AWS4";
    private const string UnsignedPayload = "UNSIGNED-PAYLOAD";
    private const string SignedHeaders = "host";
    private const string HttpMethodName = "GET";
    private const string DateFormat = "yyyyMMdd";
    private const string TimestampFormat = "yyyyMMddTHHmmssZ";
    private const string ObjectKeySeparator = "/";
    private const int UrlLifetimeSeconds = 900;
    private const string CredentialFormat = "{0}/{1}/{2}/{3}/{4}";
    private const string ScopeFormat = "{0}/{1}/{2}/{3}";
    private const string HostHeaderFormat = "host:{0}:{1}";
    private const string PathFormat = "/{0}/{1}";
    private const string QueryFormat = "X-Amz-Algorithm={0}&X-Amz-Credential={1}&X-Amz-Date={2}&X-Amz-Expires={3}&X-Amz-SignedHeaders={4}";
    private const string CanonicalRequestFormat = "{0}\n{1}\n{2}\n{3}\n\n{4}\n{5}";
    private const string StringToSignFormat = "{0}\n{1}\n{2}\n{3}";
    private const string UrlFormat = "http://{0}:{1}{2}?{3}&X-Amz-Signature={4}";

    private readonly HostConfiguration _hostConfiguration;
    private readonly string _regionName;
    private readonly TimeProvider _timeProvider;

    public MediaUrlMinter(HostConfiguration hostConfiguration, Ec2Configuration ec2Configuration, TimeProvider timeProvider)
    {
        _hostConfiguration = hostConfiguration;
        _regionName = ec2Configuration.Region.Name;
        _timeProvider = timeProvider;
    }

    public string For(string bucketName, string key)
    {
        var signingTime = _timeProvider.GetUtcNow().UtcDateTime;
        var timestamp = signingTime.ToString(TimestampFormat, CultureInfo.InvariantCulture);
        var dateStamp = signingTime.ToString(DateFormat, CultureInfo.InvariantCulture);
        var escapedKey = string.Join(ObjectKeySeparator, key.Split(ObjectKeySeparator).Select(segment => Uri.EscapeDataString(segment)));
        var credential = string.Format(CultureInfo.InvariantCulture, CredentialFormat, _hostConfiguration.Credentials.AccessKeyId, dateStamp, _regionName, ServiceName, Terminator);
        var query = string.Format(CultureInfo.InvariantCulture, QueryFormat, Algorithm, Uri.EscapeDataString(credential), timestamp, UrlLifetimeSeconds, SignedHeaders);
        var hostHeader = string.Format(CultureInfo.InvariantCulture, HostHeaderFormat, _hostConfiguration.ContainerHostName, _hostConfiguration.ListenerPort);
        var canonicalUri = string.Format(CultureInfo.InvariantCulture, PathFormat, bucketName, escapedKey);
        var canonicalRequest = string.Format(CultureInfo.InvariantCulture, CanonicalRequestFormat, HttpMethodName, canonicalUri, query, hostHeader, SignedHeaders, UnsignedPayload);
        var signature = ToSignature(canonicalRequest, dateStamp, timestamp);
        var url = string.Format(CultureInfo.InvariantCulture, UrlFormat, _hostConfiguration.ContainerHostName, _hostConfiguration.ListenerPort, canonicalUri, query, signature);

        return url;
    }

    private string ToSignature(string canonicalRequest, string dateStamp, string timestamp)
    {
        var requestHash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonicalRequest)));
        var scope = string.Format(CultureInfo.InvariantCulture, ScopeFormat, dateStamp, _regionName, ServiceName, Terminator);
        var stringToSign = string.Format(CultureInfo.InvariantCulture, StringToSignFormat, Algorithm, timestamp, scope, requestHash);
        var dateKey = HMACSHA256.HashData(Encoding.UTF8.GetBytes(SigningKeyPrefix + _hostConfiguration.Credentials.SecretAccessKey), Encoding.UTF8.GetBytes(dateStamp));
        var regionKey = HMACSHA256.HashData(dateKey, Encoding.UTF8.GetBytes(_regionName));
        var serviceKey = HMACSHA256.HashData(regionKey, Encoding.UTF8.GetBytes(ServiceName));
        var signingKey = HMACSHA256.HashData(serviceKey, Encoding.UTF8.GetBytes(Terminator));
        var signature = Convert.ToHexStringLower(HMACSHA256.HashData(signingKey, Encoding.UTF8.GetBytes(stringToSign)));

        return signature;
    }
}
