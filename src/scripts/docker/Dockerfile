# escape=`

FROM mcr.microsoft.com/dotnet/framework/runtime:4.8.1-windowsservercore-ltsc2022

SHELL ["cmd", "/S", "/C"]

RUN mkdir C:\vs_buildtools

RUN curl -SL --output C:\vs_buildtools\vs_buildtools.exe https://aka.ms/vs/17/release/vs_buildtools.exe 

COPY run-layout.ps1 C:\run-layout.ps1

RUN powershell -File C:\run-layout.ps1

COPY startup.ps1 C:\startup.ps1

CMD ["powershell.exe", "-File", "C:\\startup.ps1"]
