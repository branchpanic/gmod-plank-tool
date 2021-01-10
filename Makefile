ifndef ENGINE_DIR
$(error ENGINE_DIR must be set to <path to common steamapps>\GarrysMod\garrysmod\bin)
endif

GMAD=$(ENGINE_DIR)\gmad.exe

addon.gma: 
	if exist _build (rd _build /S /Q)
	md _build
	copy .\addon.json .\_build\addon.json
	echo D | xcopy .\lua .\_build\lua /E /Y
	echo D | xcopy .\materials .\_build\materials /E /Y
	echo D | xcopy .\models .\_build\models /E /Y
	$(GMAD) create -folder .\_build -out $@
	rd _build /S /Q
