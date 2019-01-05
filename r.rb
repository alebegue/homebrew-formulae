class R < Formula
  desc "Software environment for statistical computing"
  homepage "https://www.r-project.org/"
  url "https://cran.r-project.org/src/base/R-3/R-3.5.2.tar.gz"
  sha256 "e53d8c3cf20f2b8d7a9c1631b6f6a22874506fb392034758b3bb341c586c5b62"

  bottle do
    sha256 "08120ed5b37e5cf4b067e03ba8cd90bd03c6c4af66d20ab96be3abe2658a4a63" => :mojave
    sha256 "406e19fb1c47097b3e4f9f36cc9f6bb211dc268aa2fb5603bfe814c11bbdf657" => :high_sierra
    sha256 "25a1bfde0afffc6e186e60a2959c2d9aba89147c4f338ba5499c04d35bbfecb7" => :sierra
  end

  depends_on "pkg-config" => :build
  depends_on "gcc" # for gfortran
  depends_on "gettext"
  depends_on "jpeg"
  depends_on "libpng"
  depends_on "pcre"
  depends_on "readline"
  depends_on "xz"
  depends_on "texinfo"
  depends_on "zlib"
  depends_on "bzip2"
  depends_on "openssl"
  depends_on "cairo" => :optional
  depends_on "libtiff" => :optional
  depends_on "openblas" => :optional
  depends_on "llvm" => :optional
  depends_on :java => :optional

  # needed to preserve executable permissions on files without shebangs
  skip_clean "lib/R/bin"

  resource "gss" do
    url "https://cloud.r-project.org/src/contrib/gss_2.1-9.tar.gz", :using => :nounzip
    mirror "https://mirror.las.iastate.edu/CRAN/src/contrib/gss_2.1-9.tar.gz"
    sha256 "2961fe61c1d3bb3fe7b8e1070d6fb1dfc5d71e0c6e8a6b7c46ff6b42867c4cf3"
  end

  def install
    # Fix dyld: lazy symbol binding failed: Symbol not found: _clock_gettime
    if MacOS.version == "10.11" && MacOS::Xcode.installed? &&
       MacOS::Xcode.version >= "8.0"
      ENV["ac_cv_have_decl_clock_gettime"] = "no"
    end

    args = [
      "--prefix=#{prefix}",
      "--enable-memory-profiling",
      "--without-cairo",
      "--without-x",
      "--with-aqua",
      "--with-lapack",
      "--enable-R-shlib",
      "SED=/usr/bin/sed", # don't remember Homebrew's sed shim
    ]

    if build.with? "llvm"
      ENV["CC"] = "#{Formula["llvm"].opt_bin}/clang"
      ENV["CXX"] = "#{Formula["llvm"].opt_bin}/clang++"

      ENV.append "CFLAGS", "-Wall -g -O2"
      ENV.append "CXXFLAGS", "-Wall -g -O2"
      ENV.append "FLAGS", "-Wall -g -O2"
      ENV.append "FCFLAGS", "-Wall -g -O2"

      ENV.append "LDFLAGS", "-L#{Formula["llvm"].opt_lib} -Wl,-rpath,#{Formula["llvm"].opt_lib}"
      ENV.append "CPPFLAGS", "-I#{Formula["llvm"].opt_include}"
    end

    if build.with? "cairo"
      args << "--with-cairo"

      ENV.append "LDFLAGS", "-L#{Formula["cairo"].opt_lib}"
      ENV.append "CPPFLAGS", "-I#{Formula["cairo"].opt_include}"
    else
      args << "--without-cairo"
    end

    if build.with? "libtiff"
      args << "--with-libtiff"
    end

    if build.with? "openblas"
      args << "--with-blas=-L#{Formula["openblas"].opt_lib} -lopenblas"
      ENV.append "LDFLAGS", "-L#{Formula["openblas"].opt_lib}"
    else
      args << "--with-blas=-framework Accelerate"
      ENV.append_to_cflags "-D__ACCELERATE__" if ENV.compiler != :clang
    end

    if build.with? "java"
      args << "--enable-java"
    else
      args << "--disable-java"
    end

    # Help CRAN packages find gettext, readline and zlib
    ["gettext", "readline", "zlib"].each do |f|
      ENV.append "CPPFLAGS", "-I#{Formula[f].opt_include}"
      ENV.append "LDFLAGS", "-L#{Formula[f].opt_lib}"
    end

    # Fix cairo detection with Quartz-only cairo
    inreplace ["configure", "m4/cairo.m4"], "cairo-xlib.h", "cairo.h"

    system "./configure", *args
    system "make"
    ENV.deparallelize do
      system "make", "install"
    end

    cd "src/nmath/standalone" do
      system "make"
      ENV.deparallelize do
        system "make", "install"
      end
    end

    r_home = lib/"R"

    # make Homebrew packages discoverable for R CMD INSTALL
    inreplace r_home/"etc/Makeconf" do |s|
      s.gsub!(/^CPPFLAGS =.*/, "\\0 -I#{HOMEBREW_PREFIX}/include")
      s.gsub!(/^LDFLAGS =.*/, "\\0 -L#{HOMEBREW_PREFIX}/lib")
      s.gsub!(/.LDFLAGS =.*/, "\\0 $(LDFLAGS)")
    end

    include.install_symlink Dir[r_home/"include/*"]
    lib.install_symlink Dir[r_home/"lib/*"]

    # avoid triggering mandatory rebuilds of r when gcc is upgraded
    inreplace lib/"R/etc/Makeconf", Formula["gcc"].prefix.realpath,
                                    Formula["gcc"].opt_prefix
  end

  def post_install
    short_version =
      `#{bin}/Rscript -e 'cat(as.character(getRversion()[1,1:2]))'`.strip
    site_library = HOMEBREW_PREFIX/"lib/R/#{short_version}/site-library"
    site_library.mkpath
    ln_s site_library, lib/"R/site-library"
  end

  test do
    assert_equal "[1] 2", shell_output("#{bin}/Rscript -e 'print(1+1)'").chomp
    assert_equal ".dylib", shell_output("#{bin}/R CMD config DYLIB_EXT").chomp

    testpath.install resource("gss")
    system bin/"R", "CMD", "INSTALL", "--library=.", Dir["gss*"].first
    assert_predicate testpath/"gss/libs/gss.so", :exist?,
                     "Failed to install gss package"
  end
end
