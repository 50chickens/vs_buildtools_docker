$ErrorActionPreference = 'Stop'

Write-Host "VS Build Tools setup in container"
Write-Host "=================================="
Write-Host ""
Write-Host "The vs_buildtools.exe is available at: C:\vs_buildtools\vs_buildtools.exe"
Write-Host ""
Write-Host "To create a layout inside the container, run:"
Write-Host "  C:\vs_buildtools\vs_buildtools.exe --layout C:\localVSlayout `\"
Write-Host "    --add Microsoft.VisualStudio.Workload.ManagedDesktop `\"
Write-Host "    --add Microsoft.VisualStudio.Workload.NetWeb `\"
Write-Host "    --lang en-US"
Write-Host ""
Write-Host "This container includes:"
Write-Host "  - .NET Framework 4.8.1"
Write-Host "  - vs_buildtools.exe (for creating offline layouts)"
Write-Host ""
Write-Host "Note: Layout creation requires internet connectivity from the container"
Write-Host "      and may require additional system resources."

exit 0






