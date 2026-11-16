function Send-Chunk($session, $remotePath, $base64, $isFirst)
{
    $null = Invoke-Command -Session $session -ScriptBlock {
        param($path, $data, $first)
        $bytes = [Convert]::FromBase64String($data)
        $mode  = [System.IO.FileMode]::Append
        if ($first)
        {
            $mode = [System.IO.FileMode]::Create
        }

        $stream = [System.IO.File]::Open($path, $mode, [System.IO.FileAccess]::Write)
        try
        {
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally
        {
            $stream.Close()
        }
    } -ArgumentList $remotePath, $base64, $isFirst
}

function Send-ChunkedFile($configuration, $session, $localFile, $remotePath)
{
    $chunkSizeBytes = $configuration.ChunkSizeBytes
    $fileBytes      = @(Get-Content -Path $localFile.FullName -AsByteStream -Raw)
    $totalBytes     = $fileBytes.Length
    $offset         = 0
    $isFirst        = $true
    Write-Log "Sending $($localFile.Name) ($totalBytes bytes) to $remotePath"

    while ($offset -lt $totalBytes)
    {
        $remainingBytes = $totalBytes - $offset
        $length         = [Math]::Min($chunkSizeBytes, $remainingBytes)
        $chunk          = $fileBytes[$offset..($offset + $length - 1)]
        $base64         = [Convert]::ToBase64String($chunk)

        Send-Chunk $session $remotePath $base64 $isFirst
        $offset  += $length
        $isFirst  = $false
    }

    if ($isFirst)
    {
        Send-Chunk $session $remotePath '' $true
    }
}
