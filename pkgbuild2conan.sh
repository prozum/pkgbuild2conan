#!/usr/bin/env bash

if [[ -z "$1" ]] ; then
    echo "No argument supplied!"
    echo "Usage: pkgbuild2conan PKGBUILD-NAME"
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
    import_build_system="CMake, "
    ;;
  *configure*)
    build_system="autotools"
    import_build_system="AutoToolsBuildEnvironment, "
    ;;
  *meson*)
    build_system="meson"
    import_build_system="Meson, "
    ;;
  *setup.py*)
    build_system="python"
    import_build_system=""
    ;;
  *)
    build_system="make"
    import_build_system="AutoToolsBuildEnvironment, "
    ;;
esac

echo -e "import os"
echo -e ""
echo -e "from conans import ConanFile, ${import_build_system}tools"
echo -e ""
echo -e "class ${pkgname_camel}Conan(ConanFile):"
echo -e "    name = \"$pkgname\""
echo -e "    version = tools.get_env(\"GIT_TAG\", \"$pkgver\")"
echo -e "    description = \"$pkgdesc\""
echo -e "    license = \"$license\""
echo -e "    settings = \"os\", \"arch\", \"compiler\", \"build_type\""
echo -e ""
echo -e "    def build_requirements(self):"
echo -e "        self.build_requires(\"generators/1.0.0@{}/stable\".format(self.user))"
case "$build_system" in
  autotools|make)
    echo -e "        self.build_requires(\"autotools/1.0.0@{}/stable\".format(self.user))"
    ;;
esac
for dep in "${makedepends[@]}"
do
  wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
  if [[ $? -ne 0 ]]; then
    wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
  fi
  depver=$(grep pkgver= /tmp/$dep.PKGBUILD | cut -b 8-)
	echo -e "        self.build_requires(\"$dep/[>=$depver]@{}/stable\".format(self.user))"
done
echo -e ""


if [[ ${#depends[@]} -ne 0 ]]; then
  echo -e "    def requirements(self):"
  for dep in "${depends[@]}"
  do
    wget https://git.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
    if [[ $? -ne 0 ]]; then
      wget https://git.archlinux.org/svntogit/community.git/plain/trunk/PKGBUILD?h=packages/$dep -qO /tmp/$dep.PKGBUILD
    fi
    depver=$(grep pkgver= /tmp/$dep.PKGBUILD | cut -b 8-)
  	echo -e "        self.requires(\"$dep/[>=$depver]@{}/stable\".format(self.user))"
  done
  echo -e ""
fi

download=$(echo "${source[0]}" | sed "s/$pkgver/{0}/g")
echo -e "    def source(self):"
echo -e "        tools.get(\"$download\".format(self.version))"
echo -e ""

echo -e "    def build(self):"
case "$build_system" in
  cmake)
    echo -e "        cmake = CMake(self, generators=\"Ninja\")"
    echo -e "        cmake.configure(source_folder=\"{}-{}\".format(self.name, self.version))"
    echo -e "        cmake.build()"
    echo -e "        cmake.install()"
    ;;
  autotools)
    echo -e "        args = ["
    echo -e "            \"--disable-static\","
    echo -e "        ]"
    echo -e "        with tools.chdir(\"{}-{}\".format(self.name, self.version)):"
    echo -e "            autotools = AutoToolsBuildEnvironment(self)"
    echo -e "            autotools.configure(args=args)"
    echo -e "            autotools.make()"
    echo -e "            autotools.install()"
    ;;
  meson)
    echo -e "        meson = Meson(self)"
    echo -e "        meson.configure(source_folder=\"{}-{}\".format(self.name, self.version))"
    echo -e "        meson.install()"
    ;;
  python)
    echo -e "        with tools.chdir(\"{}-{}\".format(self.name, self.version)):"
    echo -e "            self.run('python setup.py install --optimize=1 --prefix= --root=\"{}\"'.format(self.package_folder))"
    ;;
  make)
    echo -e "        with tools.chdir(\"{}-{}\".format(self.name, self.version)):"
    echo -e "            autotools = AutoToolsBuildEnvironment(self)"
    echo -e "            autotools.make()"
    echo -e "            autotools.install()"
    ;;
esac