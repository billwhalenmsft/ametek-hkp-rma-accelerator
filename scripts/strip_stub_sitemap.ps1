param([Parameter(Mandatory)][string[]]$ZipPaths)

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Strip-StubFromZip {
    param([string]$path)
    $bk = "$path.bak"
    Copy-Item $path $bk -Force
    Write-Host "Backup: $bk"

    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
    try {
        foreach ($entryName in @('customizations.xml','solution.xml')) {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
            if (-not $entry) {
                Write-Host ("  {0}: not in zip" -f $entryName)
                continue
            }
            $sr = New-Object System.IO.StreamReader($entry.Open())
            $content = $sr.ReadToEnd()
            $sr.Dispose()
            $orig = $content.Length

            if ($entryName -eq 'customizations.xml') {
                $content = [regex]::Replace($content, '<AppModuleSiteMap>\s*<SiteMapUniqueName>bw_RMAOperations</SiteMapUniqueName>.*?</AppModuleSiteMap>', '', 'Singleline')
            } else {
                # solution.xml RootComponent for stub sitemap (by schemaName OR by id)
                $content = [regex]::Replace($content, '<RootComponent\s+type="62"\s+schemaName="bw_RMAOperations"[^/]*/>', '', 'Singleline')
                $content = [regex]::Replace($content, '<RootComponent\s+type="62"\s+id="\{?096cd8e3-194e-f111-bec6-000d3a5aed87\}?"[^/]*/>', '', 'Singleline')
            }

            $newLen = $content.Length
            if ($newLen -ne $orig) {
                $entry.Delete()
                $newEntry = $zip.CreateEntry($entryName)
                $sw = New-Object System.IO.StreamWriter($newEntry.Open())
                $sw.Write($content)
                $sw.Dispose()
                Write-Host ("  {0}: {1} -> {2} bytes (stripped)" -f $entryName, $orig, $newLen)
            } else {
                Write-Host ("  {0}: {1} bytes (no match, unchanged)" -f $entryName, $orig)
            }
        }
    } finally {
        $zip.Dispose()
    }
}

foreach ($p in $ZipPaths) {
    Write-Host "=== $p ==="
    Strip-StubFromZip -path (Resolve-Path $p).Path
}
