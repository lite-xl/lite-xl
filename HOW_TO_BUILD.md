cd /c/Users/bijim/cursor-xl

bash scripts/build.sh



CLEANING:
rm -rf build-x86_64-windows

REBUILDLING:
cd /c/Users/bijim/cursor-xl
rm -rf build-x86_64-windows
bash scripts/build.sh



LPM STUFF:
cd build-x86_64-windows
./lpm install language_server_protocol

