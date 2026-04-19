# Package-Mod.ps1
# Packages the ItemColorCoding folder into a .vmz file (zip archive).
# Run from the repo root: .\Package-Mod.ps1

$modFolder  = "ItemColorCoding"
$outputName = "ItemColorCoding.vmz"

if (-not (Test-Path $modFolder)) {
    Write-Error "Folder '$modFolder' not found. Run this script from the repo root."
    exit 1
}

# Remove previous build if it exists
if (Test-Path $outputName) {
    Remove-Item $outputName -Force
}

# Use Python to build the zip with forward-slash paths (required by Metro Mod Loader)
$pythonScript = @"
import zipfile, os, pathlib
mod_folder = r'$modFolder'
output = r'$outputName'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(mod_folder):
        for file in files:
            abs_path = os.path.join(root, file)
            p = pathlib.Path(abs_path)
            rel_from_folder = p.relative_to(mod_folder).as_posix()
            # mod.txt goes at archive root; everything else keeps the mod_folder prefix
            if rel_from_folder == 'mod.txt':
                arcname = 'mod.txt'
            else:
                arcname = mod_folder + '/' + rel_from_folder
            zf.write(abs_path, arcname)
print('Built: ' + output)
"@

python -c $pythonScript
