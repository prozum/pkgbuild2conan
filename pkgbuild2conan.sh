#!/usr/bin/env bash

# Print config.yml argument
if [ "$1" == "-c" ]; then
    print_config=1
    shift
fi

if [[ -z "$1" ]] ; then
    echo "No argument supplied!"
    echo "Usage: pkgbuild2conan [-c] PKGBUILD-NAME"
    exit 1
fi

pkg="${1//+/%2B}"

# Load PKGBUILD
wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$pkg -qO /tmp/$pkg.PKGBUILD
if [[ $? -ne 0 ]]; then
  wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$pkg -qO /tmp/$pkg.PKGBUILD
fi
if [[ $? -ne 0 ]]; then
  wget https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=$pkg -qO /tmp/$pkg.PKGBUILD
fi
source /tmp/$pkg.PKGBUILD

# Print config.yml
if [[ $print_config -eq 1 ]]; then
  echo -e "versions:"
  echo -e "  \"$pkgver\":"
  echo -e "    folder: all"
  exit 0
fi

# Gather package name
if [ -n "$pkgbase" ]; then
    pkgname=$pkgbase
fi
pkgname_camel=$(echo "$pkgname" | awk -F"-" '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}} 1' OFS="")

# Gather build system commands
build=$(declare -f build | sed -e '1,2d;$ d;s/^[ \t]*//')
case "$build" in
  *cmake*)
    build_system="cmake"
    ;;
  *configure*)
    build_system="autotools"
    ;;
  *meson*)
    build_system="meson"
    ;;
  *setup.py*)
    build_system="python"
    ;;
  *npm*)
    build_system="npm"
    ;;
  *)
    build_system="make"
    ;;
esac

# Handle npm packages without build function
package=$(declare -f package | sed -e '1,2d;$ d;s/^[ \t]*//')
case "$package" in
  *npm*)
    if [ "$build_system" == "make" ]; then
      build_system="npm"
    fi
    ;;
esac

# Output Conan recipe
echo -e "from conans import *"
echo -e ""
echo -e ""
echo -e "class ${pkgname_camel}Conan(ConanFile):"
echo -e "    name = \"$pkgname\""
echo -e "    description = \"$pkgdesc\""
echo -e "    license = \"$license\""
echo -en "    settings = {\"os\": [\"Linux\"]"
if [ "${arch[0]}" != "any" ]; then
  echo -en ", \"arch\": [\"x86_64\", \"armv8\"]"
fi
echo -e "}"

if [[ ${#depends[@]} -ne 0 ]]; then
  echo -e "    build_requires = ("
  case "$build_system" in
    autotools|make)
      echo -e "        \"autotools/[^1.0.0]\","
      ;;
  esac

  for dep in "${makedepends[@]}"
  do
    wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
    if [[ $? -ne 0 ]]; then
      wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
    fi
    depver=$(grep pkgver= /tmp/$dep.PKGBUILD | cut -b 8-)
  	echo -e "        \"$dep/[^$depver]\","
  done
  echo -e "    )"
fi

echo -e "    requires = ("
echo -e "        \"generators/[^1.0.0]\","
for dep in "${depends[@]}"
do
  wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
  if [[ $? -ne 0 ]]; then
    wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
  fi
  depver=$(grep pkgver= /tmp/$dep.PKGBUILD | cut -b 8-)
	echo -e "        \"$dep/[^$depver]\","
done
echo -e "    )"

download=$(echo "${source[0]}" | sed "s/$pkgver/{self.version}/g")
echo -e ""
echo -e "    def source(self):"

case "$build_system" in
  npm)
    echo -e "        tools.download(f\"$download\", f\"{self.name}-{self.version}.tgz\")"
    ;;
  *)
    echo -e "        tools.get(f\"$download\")"
    ;;
esac

echo -e ""
echo -e "    def build(self):"
case "$build_system" in
  cmake)
    echo -e "        cmake = CMake(self, generators=\"Ninja\")"
    echo -e "        cmake.configure(source_folder=f\"{self.name}-{self.version}\")"
    echo -e "        cmake.build()"
    echo -e "        cmake.install()"
    ;;
  autotools)
    echo -e "        args = ["
    echo -e "            \"--disable-static\","
    echo -e "        ]"
    echo -e "        autotools = AutoToolsBuildEnvironment(self)"
    echo -e "        autotools.configure(args=args, configure_dir=f\"{self.name}-{self.version}\")"
    echo -e "        autotools.make()"
    echo -e "        autotools.install()"
    ;;
  meson)
    echo -e "        meson = Meson(self)"
    echo -e "        meson.configure(source_folder=f\"{self.name}-{self.version}\")"
    echo -e "        meson.install()"
    ;;
  python)
    echo -e "        with tools.chdir(f\"{self.name}-{self.version}\"):"
    echo -e "            self.run(f'python setup.py install --optimize=1 --prefix= --root=\"{self.package_folder}\"')"
    ;;
  npm)
    echo -e "        self.run(f'npm install -g --user root --prefix \"{self.package_folder}\" \"{self.name}-{self.version}.tgz\"')"
    ;;
  make)
    echo -e "        with tools.chdir(f\"{self.name}-{self.version}\"):"
    echo -e "            autotools = AutoToolsBuildEnvironment(self)"
    echo -e "            autotools.make()"
    echo -e "            autotools.install()"
    ;;
esac