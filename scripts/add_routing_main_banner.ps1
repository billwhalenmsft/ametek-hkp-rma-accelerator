$org='https://org6feab6b5.crm.dynamics.com'
$t=az account get-access-token --resource $org --query accessToken -o tsv
$hg=@{Authorization="Bearer $t";Accept='application/json'}
$hp=@{Authorization="Bearer $t";'Content-Type'='application/json; charset=utf-8';'If-Match'='*'}
$id='7baee065-15eb-4890-9551-9cf3ca5e759d'
$banner='How this works: IF an incoming claim matches the Rule Type + Match Value below, THEN assign it to the chosen plant. Lower Priority numbers evaluate first.'
$cur=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($id)?`$select=formxml" -Headers $hg
$xml=$cur.formxml
$sectId='{c9d877b6-baed-4750-a1b2-a1cb590e0b95}'
$xml=$xml -replace ('showlabel="false" showbar="false" IsUserDefined="0" id="'+[regex]::Escape($sectId)+'"'),('showlabel="true" showbar="false" IsUserDefined="0" id="'+$sectId+'"')
$pos=$xml.IndexOf($sectId)
$labelStart=$xml.IndexOf('<label description="General"',$pos)
$labelEnd=$xml.IndexOf('/>',$labelStart)+2
$xml=$xml.Substring(0,$labelStart)+"<label description=`"$banner`" languagecode=`"1033`" />"+$xml.Substring($labelEnd)
$body=@{formxml=$xml;formjson=$null}|ConvertTo-Json -Depth 5 -Compress
Invoke-WebRequest -Uri "$org/api/data/v9.2/systemforms($id)" -Method Patch -Headers $hp -Body $body -UseBasicParsing|Out-Null
$px='<importexportxml><entities><entity>rma_routingrule</entity></entities></importexportxml>'
Invoke-WebRequest -Uri "$org/api/data/v9.2/PublishXml" -Method Post -Headers $hp -Body (@{ParameterXml=$px}|ConvertTo-Json) -UseBasicParsing|Out-Null
Write-Host "Main form banner set + published" -ForegroundColor Green
