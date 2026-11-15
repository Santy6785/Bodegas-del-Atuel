<#
Mide el tiempo de respuesta de los endpoints de reportes (S1, S6, S7, S8).

Requisitos: la API levantada contra la base cargada (bodegas_atuel_bench).
Uso, desde la raiz del repo:
  .\scripts\perf\medir_reportes.ps1 -Sala 1 -Repeticiones 5

Por cada endpoint hace 1 llamada inicial (primera, caliente la conexion y el
cache) y despues N repeticiones. Informa primera, mediana, minimo y maximo en ms.
Guarda el resultado en scratch\tiempos_reportes.csv.
#>
param(
  [string]$Base = "http://localhost:8000",
  [int]$Sala = 1,
  [int]$Repeticiones = 5
)

$inv = [System.Globalization.CultureInfo]::InvariantCulture

# Ajustar las rutas si el listado de rutas de la API muestra otras.
$endpoints = @(
  @{ Codigo = "S1"; Nombre = "Top 10 vinos mas vendidos";         Ruta = "/reportes/top-vinos" },
  @{ Codigo = "S6"; Nombre = "Vinos sin stock en una sala";       Ruta = "/reportes/vinos-sin-stock?id_sala=$Sala" },
  @{ Codigo = "S7"; Nombre = "Transportista con mayor actividad"; Ruta = "/reportes/transportista-activo" },
  @{ Codigo = "S8"; Nombre = "Ventas por sala (ultimo trimestre)"; Ruta = "/reportes/ventas-por-sala?periodo=ultimo_trimestre" },
  @{ Codigo = "S8-total"; Nombre = "Ventas por sala (sin filtro de fecha)"; Ruta = "/reportes/ventas-por-sala" }
)

$filas = @()

foreach ($e in $endpoints) {
  $url = "$($Base)$($e.Ruta)"
  $tiempos = @()
  $codigo = ""
  $bytes = "0"

  for ($i = 1; $i -le ($Repeticiones + 1); $i++) {
    $salida = curl.exe -s -o NUL -w "%{http_code};%{time_total};%{size_download}" $url
    $partes = $salida.Split(";")
    $codigo = $partes[0]
    $bytes = $partes[2]
    $tiempos += [math]::Round([double]::Parse($partes[1], $inv) * 1000, 1)
  }

  if ($codigo -ne "200") {
    Write-Warning "$($e.Codigo): respondio HTTP $codigo en $url (revisar antes de usar estos tiempos)"
  }

  $primera = $tiempos[0]
  $resto = @($tiempos[1..$Repeticiones] | Sort-Object)
  $n = $resto.Count
  if ($n % 2 -eq 1) {
    $mediana = $resto[($n - 1) / 2]
  } else {
    $mediana = ($resto[$n / 2 - 1] + $resto[$n / 2]) / 2
  }

  $filas += [pscustomobject]@{
    Codigo     = $e.Codigo
    Reporte    = $e.Nombre
    Ruta       = $e.Ruta
    HTTP       = $codigo
    Bytes      = $bytes
    Primera_ms = $primera
    Mediana_ms = [math]::Round($mediana, 1)
    Min_ms     = $resto[0]
    Max_ms     = $resto[$n - 1]
  }
}

$filas | Format-Table -AutoSize

New-Item -ItemType Directory -Path scratch -ErrorAction SilentlyContinue | Out-Null
$filas | Export-Csv -Path scratch\tiempos_reportes.csv -NoTypeInformation -Encoding UTF8
Write-Host "Guardado en scratch\tiempos_reportes.csv"

Write-Host ""
Write-Host "Tabla en Markdown (para pegar en el informe):"
Write-Host "| Codigo | Reporte | HTTP | Primera (ms) | Mediana (ms) | Min (ms) | Max (ms) |"
Write-Host "|---|---|---|---|---|---|---|"
foreach ($f in $filas) {
  Write-Host "| $($f.Codigo) | $($f.Reporte) | $($f.HTTP) | $($f.Primera_ms) | $($f.Mediana_ms) | $($f.Min_ms) | $($f.Max_ms) |"
}
