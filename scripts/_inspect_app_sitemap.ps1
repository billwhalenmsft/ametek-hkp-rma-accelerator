$orgUrl="https://org6feab6b5.crm.dynamics.com"
$token=(az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h=@{Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0"}
$wrId="3e90c034-2150-f111-a824-0022480a5e8d"
$appId="8661f960-1f4e-f111-bec6-000d3a5aed87"

Write-Host "=== Solutions containing the MDA app ===" -ForegroundColor Cyan
$appSols=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/solutioncomponents?`$filter=objectid eq $appId&`$expand=solutionid(`$select=uniquename,friendlyname,solutionid,ismanaged)" -Headers $h).value
foreach ($s in $appSols) { Write-Host "  $($s.solutionid.uniquename) [managed=$($s.solutionid.ismanaged)] $($s.solutionid.solutionid)" }

Write-Host "`n=== Unmanaged RMA-ish solutions ===" -ForegroundColor Cyan
(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/solutions?`$filter=ismanaged eq false and (contains(uniquename,'rma') or contains(friendlyname,'RMA'))&`$select=uniquename,friendlyname,solutionid" -Headers $h).value | Format-Table uniquename,friendlyname,solutionid -AutoSize

Write-Host "`n=== MDA app metadata ===" -ForegroundColor Cyan
$app=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/appmodules($appId)?`$select=name,uniquename,appmoduleid,appmoduleidunique,clienttype" -Headers $h)
$app | Format-List name,uniquename,appmoduleidunique,clienttype

Write-Host "=== Linked sitemap ===" -ForegroundColor Cyan
$smLinks=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/appmodulecomponents?`$filter=_appmoduleidunique_value eq $($app.appmoduleidunique) and componenttype eq 62&`$select=objectid,componenttype,appmodulecomponentid" -Headers $h).value
foreach ($x in $smLinks) { Write-Host "  sitemap objectid=$($x.objectid) appmodulecomponentid=$($x.appmodulecomponentid)" }

if ($smLinks.Count -gt 0) {
    $sitemapId = $smLinks[0].objectid
    Write-Host "`n=== Sitemap XML (first 800 chars) ===" -ForegroundColor Cyan
    $sm = (Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/sitemaps($sitemapId)?`$select=sitemapname,sitemapxml" -Headers $h)
    Write-Host "Name: $($sm.sitemapname)"
    Write-Host $sm.sitemapxml.Substring(0, [Math]::Min(800, $sm.sitemapxml.Length))
    $outDir = "customers/ametek/hkp_rma/backup"
    $outFile = "$outDir/sitemap_${sitemapId}_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
    [System.IO.File]::WriteAllText((Resolve-Path $outDir).Path + "\sitemap_${sitemapId}_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml", $sm.sitemapxml)
    Write-Host "`n  -> backed up sitemap to $outFile"
}
