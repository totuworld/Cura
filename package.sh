#!/bin/bash

# This script is to package the Cura package for Windows/Linux and Mac OS X
# This script should run under Linux and Mac OS X, as well as Windows with Cygwin.

#############################
# CONFIGURATION
#############################

##Select the build target
BUILD_TARGET=${1:-all}
#BUILD_TARGET=win32
#BUILD_TARGET=linux
#BUILD_TARGET=darwin
#BUILD_TARGET=debian

##Do we need to create the final archive
ARCHIVE_FOR_DISTRIBUTION=1
##Which version name are we appending to the final archive
BUILD_NAME=13.06.5
TARGET_DIR=Cura-${BUILD_NAME}-${BUILD_TARGET}

##Which versions of external programs to use
WIN_PORTABLE_PY_VERSION=2.7.2.1

#############################
# Support functions
#############################
function checkTool
{
	if [ -z `which $1` ]; then
		echo "The $1 command must be somewhere in your \$PATH."
		echo "Fix your \$PATH or install $2"
		exit 1
	fi
}

function downloadURL
{
	filename=`basename "$1"`
	echo "Checking for $filename"
	if [ ! -f "$filename" ]; then
		echo "Downloading $1"
		curl -L -O "$1"
		if [ $? != 0 ]; then
			echo "Failed to download $1"
			exit 1
		fi
	fi
}

function extract
{
	echo "Extracting $*"
	echo "7z x -y $*" >> log.txt
	7z x -y $* >> log.txt
}

#############################
# Actual build script
#############################
if [ "$BUILD_TARGET" = "all" ]; then
	$0 win32
	$0 linux
	$0 darwin
	exit
fi

# Change working directory to the directory the script is in
# http://stackoverflow.com/a/246128
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR

checkTool git "git: http://git-scm.com/"
checkTool curl "curl: http://curl.haxx.se/"
if [ $BUILD_TARGET = "win32" ]; then
	#Check if we have 7zip, needed to extract and packup a bunch of packages for windows.
	checkTool 7z "7zip: http://www.7-zip.org/"
	checkTool mingw32-make "mingw: http://www.mingw.org/"
fi
#For building under MacOS we need gnutar instead of tar
if [ -z `which gnutar` ]; then
	TAR=tar
else
	TAR=gnutar
fi


#############################
# Darwin
#############################

if [ "$BUILD_TARGET" = "darwin" ]; then
    TARGET_DIR=Cura-${BUILD_NAME}-MacOS

	rm -rf scripts/darwin/build
	rm -rf scripts/darwin/dist

	python build_app.py py2app
	rc=$?
	if [[ $rc != 0 ]]; then
		echo "Cannot build app."
		exit 1
	fi

    #Add cura version file (should read the version from the bundle with pyobjc, but will figure that out later)
    echo $BUILD_NAME > scripts/darwin/dist/Cura.app/Contents/Resources/version
	rm -rf CuraEngine
	git clone https://github.com/Ultimaker/CuraEngine
	make -C CuraEngine
	cp CuraEngine/CuraEngine scripts/darwin/dist/Cura.app/Contents/Resources/CuraEngine

	cd scripts/darwin

	# Install QuickLook plugin
	mkdir -p dist/Cura.app/Contents/Library/QuickLook
	cp -a STLQuickLook.qlgenerator dist/Cura.app/Contents/Library/QuickLook/

	# Archive app
	cd dist
	$TAR cfp - Cura.app | gzip --best -c > ../../../${TARGET_DIR}.tar.gz
	cd ..

	# Create sparse image for distribution
	hdiutil detach /Volumes/Cura\ -\ Ultimaker/
	rm -rf Cura.dmg.sparseimage
	hdiutil convert DmgTemplateCompressed.dmg -format UDSP -o Cura.dmg
	hdiutil resize -size 500m Cura.dmg.sparseimage
	hdiutil attach Cura.dmg.sparseimage
	cp -a dist/Cura.app /Volumes/Cura\ -\ Ultimaker/Cura/
	hdiutil detach /Volumes/Cura\ -\ Ultimaker
	hdiutil convert Cura.dmg.sparseimage -format UDZO -imagekey zlib-level=9 -ov -o ../../${TARGET_DIR}.dmg
	exit
fi

#############################
# Debian .deb
#############################

if [ "$BUILD_TARGET" = "debian" ]; then
	git clone https://github.com/GreatFruitOmsk/Power
	git clone https://github.com/Ultimaker/CuraEngine
	make -C CuraEngine
	rm -rf scripts/linux/debian/usr/share/cura
	mkdir -p scripts/linux/debian/usr/share/cura
	cp -a Cura scripts/linux/debian/usr/share/cura/
	cp -a CuraEngine/CuraEngine scripts/linux/debian/usr/share/cura/
	cp scripts/linux/cura.py scripts/linux/debian/usr/share/cura/
	cp -a Power/power scripts/linux/debian/usr/share/cura/
	echo $BUILD_NAME > scripts/linux/debian/usr/share/cura/Cura/version
	sudo chown root:root scripts/linux/debian -R
	sudo chmod 755 scripts/linux/debian/DEBIAN/*
	cd scripts/linux
	dpkg-deb --build debian ${TARGET_DIR}.deb
	sudo chown `id -un`:`id -gn` debian -R
	exit
fi

#############################
# Rest
#############################

#############################
# Download all needed files.
#############################

if [ $BUILD_TARGET = "win32" ]; then
	#Get portable python for windows and extract it. (Linux and Mac need to install python themselfs)
	downloadURL http://ftp.nluug.nl/languages/python/portablepython/v2.7/PortablePython_${WIN_PORTABLE_PY_VERSION}.exe
	downloadURL http://sourceforge.net/projects/pyserial/files/pyserial/2.5/pyserial-2.5.win32.exe
	downloadURL http://sourceforge.net/projects/pyopengl/files/PyOpenGL/3.0.1/PyOpenGL-3.0.1.win32.exe
	downloadURL http://sourceforge.net/projects/numpy/files/NumPy/1.6.2/numpy-1.6.2-win32-superpack-python2.7.exe
	downloadURL http://videocapture.sourceforge.net/VideoCapture-0.9-5.zip
	downloadURL http://ffmpeg.zeranoe.com/builds/win32/static/ffmpeg-20120927-git-13f0cd6-win32-static.7z
	downloadURL http://sourceforge.net/projects/comtypes/files/comtypes/0.6.2/comtypes-0.6.2.win32.exe
	downloadURL http://www.uwe-sieber.de/files/ejectmedia.zip
	#Get the power module for python
	rm -rf Power
	git clone https://github.com/GreatFruitOmsk/Power
	rm -rf CuraEngine
	git clone https://github.com/Ultimaker/CuraEngine
fi

#############################
# Build the packages
#############################
rm -rf ${TARGET_DIR}
mkdir -p ${TARGET_DIR}

rm -f log.txt
if [ $BUILD_TARGET = "win32" ]; then
	#For windows extract portable python to include it.
	extract PortablePython_${WIN_PORTABLE_PY_VERSION}.exe \$_OUTDIR/App
	extract PortablePython_${WIN_PORTABLE_PY_VERSION}.exe \$_OUTDIR/Lib/site-packages
	extract pyserial-2.5.win32.exe PURELIB
	extract PyOpenGL-3.0.1.win32.exe PURELIB
	extract numpy-1.6.2-win32-superpack-python2.7.exe numpy-1.6.2-sse2.exe
	extract numpy-1.6.2-sse2.exe PLATLIB
	extract VideoCapture-0.9-5.zip VideoCapture-0.9-5/Python27/DLLs/vidcap.pyd
	extract ffmpeg-20120927-git-13f0cd6-win32-static.7z ffmpeg-20120927-git-13f0cd6-win32-static/bin/ffmpeg.exe
	extract ffmpeg-20120927-git-13f0cd6-win32-static.7z ffmpeg-20120927-git-13f0cd6-win32-static/licenses
	extract comtypes-0.6.2.win32.exe
	extract ejectmedia.zip Win32

	mkdir -p ${TARGET_DIR}/python
	mkdir -p ${TARGET_DIR}/Cura/
	mv \$_OUTDIR/App/* ${TARGET_DIR}/python
	mv \$_OUTDIR/Lib/site-packages/wx* ${TARGET_DIR}/python/Lib/site-packages/
	mv PURELIB/serial ${TARGET_DIR}/python/Lib
	mv PURELIB/OpenGL ${TARGET_DIR}/python/Lib
	mv PURELIB/comtypes ${TARGET_DIR}/python/Lib
	mv PLATLIB/numpy ${TARGET_DIR}/python/Lib
	mv Power/power ${TARGET_DIR}/python/Lib
	mv VideoCapture-0.9-5/Python27/DLLs/vidcap.pyd ${TARGET_DIR}/python/DLLs
	mv ffmpeg-20120927-git-13f0cd6-win32-static/bin/ffmpeg.exe ${TARGET_DIR}/Cura/
	mv ffmpeg-20120927-git-13f0cd6-win32-static/licenses ${TARGET_DIR}/Cura/ffmpeg-licenses/
	mv Win32/EjectMedia.exe ${TARGET_DIR}/Cura/
	
	rm -rf Power/
	rm -rf \$_OUTDIR
	rm -rf PURELIB
	rm -rf PLATLIB
	rm -rf VideoCapture-0.9-5
	rm -rf numpy-1.6.2-sse2.exe
	rm -rf ffmpeg-20120927-git-13f0cd6-win32-static

	#Clean up portable python a bit, to keep the package size down.
	rm -rf ${TARGET_DIR}/python/PyScripter.*
	rm -rf ${TARGET_DIR}/python/Doc
	rm -rf ${TARGET_DIR}/python/locale
	rm -rf ${TARGET_DIR}/python/tcl
	rm -rf ${TARGET_DIR}/python/Lib/test
	rm -rf ${TARGET_DIR}/python/Lib/distutils
	rm -rf ${TARGET_DIR}/python/Lib/site-packages/wx-2.8-msw-unicode/wx/tools
	rm -rf ${TARGET_DIR}/python/Lib/site-packages/wx-2.8-msw-unicode/wx/locale
	#Remove the gle files because they require MSVCR71.dll, which is not included. We also don't need gle, so it's safe to remove it.
	rm -rf ${TARGET_DIR}/python/Lib/OpenGL/DLLS/gle*

    #Build the C++ engine
	mingw32-make -C CuraEngine
fi

#add Cura
mkdir -p ${TARGET_DIR}/Cura
cp -a Cura/* ${TARGET_DIR}/Cura
#Add cura version file
echo $BUILD_NAME > ${TARGET_DIR}/Cura/version

#add script files
if [ $BUILD_TARGET = "win32" ]; then
    cp -a scripts/${BUILD_TARGET}/*.bat $TARGET_DIR/
    cp CuraEngine/CuraEngine.exe $TARGET_DIR
else
    cp -a scripts/${BUILD_TARGET}/*.sh $TARGET_DIR/
fi

#package the result
if (( ${ARCHIVE_FOR_DISTRIBUTION} )); then
	if [ $BUILD_TARGET = "win32" ]; then
		#rm ${TARGET_DIR}.zip
		#cd ${TARGET_DIR}
		#7z a ../${TARGET_DIR}.zip *
		#cd ..

		if [ ! -z `which wine` ]; then
			#if we have wine, try to run our nsis script.
			rm -rf scripts/win32/dist
			ln -sf `pwd`/${TARGET_DIR} scripts/win32/dist
			wine ~/.wine/drive_c/Program\ Files/NSIS/makensis.exe /DVERSION=${BUILD_NAME} scripts/win32/installer.nsi
			mv scripts/win32/Cura_${BUILD_NAME}.exe ./
		fi
		if [ -f '/cygdrive/c/Program Files (x86)/NSIS/makensis.exe' ]; then
			rm -rf scripts/win32/dist
			mv `pwd`/${TARGET_DIR} scripts/win32/dist
			'/cygdrive/c/Program Files (x86)/NSIS/makensis.exe' -DVERSION=${BUILD_NAME} 'scripts/win32/installer.nsi' >> log.txt
			mv scripts/win32/Cura_${BUILD_NAME}.exe ./
		fi
	else
		echo "Archiving to ${TARGET_DIR}.tar.gz"
		$TAR cfp - ${TARGET_DIR} | gzip --best -c > ${TARGET_DIR}.tar.gz
	fi
else
	echo "Installed into ${TARGET_DIR}"
fi
