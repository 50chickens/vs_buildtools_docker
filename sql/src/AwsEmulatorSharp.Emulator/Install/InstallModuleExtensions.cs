using Microsoft.Extensions.DependencyInjection;

namespace AwsEmulatorSharp.Emulator.Install;

public static class InstallModuleExtensions
{
    public static IServiceCollection AddInstallModule(this IServiceCollection services)
    {
        var configurationReader = new InstallConfigurationReader();
        var configuration = configurationReader.Read();

        services.AddSingleton(configuration);
        services.AddSingleton<MediaUrlMinter>();
        services.AddSingleton<InstallPlanGenerator>();

        return services;
    }
}
