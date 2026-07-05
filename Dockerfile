# escape=`

# Use the latest .NET Framework runtime image.
FROM mcr.microsoft.com/dotnet/framework/runtime:4.8.1-windowsservercore-ltsc2022

# Restore the default Windows shell for correct batch processing.
SHELL ["cmd", "/S", "/C"]

RUN curl -SL --output vs_buildtools.exe https://aka.ms/vs/stable/vs_buildtools.exe 
RUN vs_buildtools.exe --quiet --wait --norestart --nocache --installPath "%ProgramFiles(x86)%\Microsoft Visual Studio\BuildTools" --add Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools