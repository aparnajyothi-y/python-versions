set -e

PYTHON_FULL_VERSION="{{__VERSION_FULL__}}"
PYTHON_PKG_NAME="{{__PKG_NAME__}}"
ARCH="{{__ARCH__}}"
MAJOR_VERSION=$(echo $PYTHON_FULL_VERSION | cut -d '.' -f 1)
MINOR_VERSION=$(echo $PYTHON_FULL_VERSION | cut -d '.' -f 2)
PATCH_VERSION=$(echo $PYTHON_FULL_VERSION | cut -d '.' -f 3)

PYTHON_MAJOR=python$MAJOR_VERSION
PYTHON_MAJOR_DOT_MINOR=python$MAJOR_VERSION.$MINOR_VERSION
PYTHON_MAJOR_MINOR=python$MAJOR_VERSION$MINOR_VERSION

# Check if the version is between 3.8.2 and 3.8.11 (exclusive of 3.8.11)
if [[ "$PYTHON_FULL_VERSION" == "3.8.2" ]] || { [[ "$PYTHON_FULL_VERSION" > "3.8.2" ]] && [[ "$PYTHON_FULL_VERSION" < "3.8.11" ]]; }; then
    echo "Python version is between 3.8.2 and 3.8.11, applying the fix..."

    if [ -z ${AGENT_TOOLSDIRECTORY+x} ]; then
        # No AGENT_TOOLSDIRECTORY on GitHub images
        TOOLCACHE_ROOT=$RUNNER_TOOL_CACHE
    else
        TOOLCACHE_ROOT=$AGENT_TOOLSDIRECTORY
    fi

    PYTHON_TOOLCACHE_PATH=$TOOLCACHE_ROOT/Python
    PYTHON_TOOLCACHE_VERSION_PATH=$PYTHON_TOOLCACHE_PATH/$PYTHON_FULL_VERSION
    PYTHON_TOOLCACHE_VERSION_ARCH_PATH=$PYTHON_TOOLCACHE_VERSION_PATH/$ARCH
    PYTHON_FRAMEWORK_PATH="/Library/Frameworks/Python.framework/Versions/${MAJOR_VERSION}.${MINOR_VERSION}"
    PYTHON_APPLICATION_PATH="/Applications/Python ${MAJOR_VERSION}.${MINOR_VERSION}"

    echo "Check if Python hostedtoolcache folder exists..."
    if [ ! -d $PYTHON_TOOLCACHE_PATH ]; then
        echo "Creating Python hostedtoolcache folder..."
        mkdir -p $PYTHON_TOOLCACHE_PATH
    else
        # Remove ALL other directories for the same major.minor Python versions
        find $PYTHON_TOOLCACHE_PATH -name "${MAJOR_VERSION}.${MINOR_VERSION}.*" | while read python_version; do
            python_version_arch="$python_version/$ARCH"
            if [ -e "$python_version_arch" ]; then
                echo "Deleting Python $python_version_arch"
                rm -rf "$python_version_arch"
            fi
        done
    fi

    echo "Install Python binaries from prebuilt package"
    sudo installer -pkg $PYTHON_PKG_NAME -target /

    # Debug: Check if the Python binary and 'bin' directory are installed
    echo "Verifying Python installation..."
    if [ ! -d "$PYTHON_FRAMEWORK_PATH/bin" ]; then
        echo "Error: Expected 'bin' directory in $PYTHON_FRAMEWORK_PATH, but it doesn't exist."
        echo "Attempting to find the Python installation directories..."
        find / -name python  # This will show where Python binaries are installed
        find / -name bin  # This will show if 'bin' exists anywhere
        exit 1
    else
        echo "Python bin directory found."
    fi

    echo "Create hostedtoolcache symlinks (Required for backward compatibility)"
    echo "Create Python $PYTHON_FULL_VERSION folder"
    mkdir -p $PYTHON_TOOLCACHE_VERSION_ARCH_PATH
    cd $PYTHON_TOOLCACHE_VERSION_ARCH_PATH

    # Ensure 'bin' directory exists before creating symlinks
    if [ ! -d "$PYTHON_FRAMEWORK_PATH/bin" ]; then
        echo "Creating missing bin directory..."
        mkdir -p "$PYTHON_FRAMEWORK_PATH/bin"
    fi

    # Create symlinks for framework components
    ln -s "${PYTHON_FRAMEWORK_PATH}/bin" bin
    ln -s "${PYTHON_FRAMEWORK_PATH}/include" include
    ln -s "${PYTHON_FRAMEWORK_PATH}/share" share
    ln -s "${PYTHON_FRAMEWORK_PATH}/lib" lib

    echo "Create additional symlinks (Required for the UsePythonVersion Azure Pipelines task and the setup-python GitHub Action)"
    ln -s ./bin/$PYTHON_MAJOR_DOT_MINOR python

    cd bin/

    # Check if 'bin' directory exists before cd
    if [ ! -d "bin" ]; then
        echo "Error: 'bin' directory does not exist. Exiting."
        exit 1
    fi

    # This symlink already exists if Python version with the same major.minor version is installed,
    # since we do not remove the framework folder
    if [ ! -f $PYTHON_MAJOR_MINOR ]; then
        ln -s $PYTHON_MAJOR_DOT_MINOR $PYTHON_MAJOR_MINOR
    fi

    # Create symlink for 'python' if it doesn't exist
    if [ ! -f python ]; then
        ln -s $PYTHON_MAJOR_DOT_MINOR python
    fi

    chmod +x ../python $PYTHON_MAJOR $PYTHON_MAJOR_DOT_MINOR $PYTHON_MAJOR_MINOR python

    echo "Upgrading pip..."
    export PIP_ROOT_USER_ACTION=ignore
    ./python -m ensurepip
    ./python -m pip install --upgrade --force-reinstall pip --disable-pip-version-check --no-warn-script-location

    echo "Install OpenSSL certificates"
    sh -e "${PYTHON_APPLICATION_PATH}/Install Certificates.command"

    echo "Create complete file"
    touch $PYTHON_TOOLCACHE_VERSION_PATH/${ARCH}.complete
else
    echo "Python version is not in the range 3.8.2 to 3.8.11. Skipping the fix."
fi
