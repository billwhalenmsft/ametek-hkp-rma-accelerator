# Strip the rma_subarea_claimnotes SubArea from RMA Operations and Monitoring sitemap.
# Bill's manual UI edit didn't actually save this change (modifiedon stayed 5/12),
# probably because modern app designer doesn't expose the legacy SubArea or
# the History group was hidden from the navigation panel.

$ErrorActionPreference = 'Stop'
$orgUrl    = "https://org6feab6b5.crm.dynamics.com"
$sitemapId = '738e4b00-214e-f111-bec6-000d3a5aed87'   # RMA Operations and Monitoring
$token     = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h         = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$hPatch    = $h + @{ 'Content-Type' = 'application/json' }

Write-Host "[1/4] Reading current sitemap..."
$sm = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/sitemaps($sitemapId)?`$select=sitemapname,sitemapxml,modifiedon" -Headers $h
Write-Host "      modifiedon: $($sm.modifiedon)"

# Backup
$backupPath = "customers/ametek/hkp_rma/backup/sitemap_RMAOpsMon_$(Get-Date -Format yyyyMMdd_HHmmss).xml"
New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
$sm.sitemapxml | Out-File $backupPath -Encoding UTF8
Write-Host "      backup: $backupPath"

if ($sm.sitemapxml -notmatch 'rma_claimnote') {
  Write-Host "      No rma_claimnote in sitemap. Nothing to do."
  return
}

Write-Host "[2/4] Removing SubArea[Entity='rma_claimnote'] nodes..."
$xml = [xml]$sm.sitemapxml
$nodes = $xml.SelectNodes("//SubArea[@Entity='rma_claimnote']")
foreach ($n in $nodes) {
  $parent = $n.ParentNode
  Write-Host "      Removing SubArea Id='$($n.Id)' from Group Id='$($parent.Id)' Title='$($parent.Title)'"
  $parent.RemoveChild($n) | Out-Null
}
# Drop now-empty Groups, then empty Areas
$emptyGroups = $xml.SelectNodes("//Group[not(SubArea)]")
foreach ($g in $emptyGroups) {
  Write-Host "      Removing now-empty Group Id='$($g.Id)' Title='$($g.Title)'"
  $g.ParentNode.RemoveChild($g) | Out-Null
}
$emptyAreas = $xml.SelectNodes("//Area[not(Group)]")
foreach ($a in $emptyAreas) {
  Write-Host "      Removing now-empty Area Id='$($a.Id)' Title='$($a.Title)'"
  $a.ParentNode.RemoveChild($a) | Out-Null
}

$newXml = $xml.OuterXml

Write-Host "[3/4] PATCHing sitemap..."
$body = @{ sitemapxml = $newXml } | ConvertTo-Json -Compress
Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/sitemaps($sitemapId)" -Method Patch -Headers $hPatch -Body $body | Out-Null
Write-Host "      [ok] Sitemap patched."

Write-Host "[4/4] PublishXml for sitemap..."
$publishBody = @{ ParameterXml = "<importexportxml><sitemaps><sitemap>$sitemapId</sitemap></sitemaps></importexportxml>" } | ConvertTo-Json -Compress
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $hPatch -Body $publishBody | Out-Null
  Write-Host "      [ok] Sitemap published."
} catch {
  Write-Host "      [WARN] PublishXml: $($_.ErrorDetails.Message)"
}

Write-Host "Done."
