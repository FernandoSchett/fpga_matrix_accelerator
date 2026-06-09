Write-Host "Compilando main.tex..."
pdflatex -interaction=nonstopmode main.tex

Write-Host "Rodando biber..."
biber main

Write-Host "Re-compilando (1/2)..."
pdflatex -interaction=nonstopmode main.tex

Write-Host "Re-compilando (2/2)..."
pdflatex -interaction=nonstopmode main.tex

Write-Host "Fim."
