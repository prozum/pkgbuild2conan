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

# Load PKGBUILD
wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$1 -qO /tmp/$1.PKGBUILD
if [[ $? -ne 0 ]]; then
  wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$1 -qO /tmp/$1.PKGBUILD
fi
if [[ $? -ne 0 ]]; then
  wget https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=$1 -qO /tmp/$1.PKGBUILD
fi
source /tmp/$1.PKGBUILD

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
  *)
    build_system="make"
    ;;
esac

echo -e "from conans import *"
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
echo -e "    build_requires = ("
echo -e "        \"generators/1.0.0\","
case "$build_system" in
  autotools|make)
    echo -e "        \"autotools/1.0.0\","
    ;;
esac
for dep in "${makedepends[@]}"
do
  wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
  if [[ $? -ne 0 ]]; then
    wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
  fi
  depver=$(grep pkgver= /tmp/$dep.PKGBUILD | cut -b 8-)
	echo -e "        \"$dep/[>=$depver]\","
done
echo -e "    )"


if [[ ${#depends[@]} -ne 0 ]]; then
  echo -e "    requires = ("
  for dep in "${depends[@]}"
  do
    wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
    if [[ $? -ne 0 ]]; then
      wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
    fi
    depver=$(grep pkgver= /tmp/$dep.PKGBUILD | cut -b 8-)
  	echo -e "        \"$dep/[>=$depver]\","
  done
  echo -e "    )"
fi

download=$(echo "${source[0]}" | sed "s/$pkgver/{self.version}/g")
echo -e ""
echo -e "    def source(self):"
echo -e "        tools.get(f\"$download\")"

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
  make)
    echo -e "        with tools.chdir(f\"{self.name}-{self.version}\"):"
    echo -e "            autotools = AutoToolsBuildEnvironment(self)"
    echo -e "            autotools.make()"
    echo -e "            autotools.install()"
    ;;
esac