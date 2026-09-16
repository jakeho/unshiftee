.PHONY: app install clean

app:
	./Scripts/build-app.sh

install: app
	mkdir -p "$(HOME)/Applications"
	/usr/bin/ditto "dist/Unshiftee.app" "$(HOME)/Applications/Unshiftee.app"
	@echo "Installed $(HOME)/Applications/Unshiftee.app"

clean:
	/usr/bin/swift package clean
	rm -rf dist
