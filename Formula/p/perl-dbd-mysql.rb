# This is an exception to Homebrew's CPAN formula policy due to the workarounds
# needed to use macOS DBI and to avoid overlinking to libraries like `zlib`.
class PerlDbdMysql < Formula
  desc "MySQL driver for the Perl5 Database Interface (DBI)"
  homepage "https://dbi.perl.org/"
  url "https://cpan.metacpan.org/authors/id/D/DV/DVEEDEN/DBD-mysql-5.010.tar.gz"
  sha256 "2ca2ff39d93e89d4f7446e5f0faf03805e9167ee9b8a04ba7cb246e2cb46eee7"
  license any_of: ["Artistic-1.0-Perl", "GPL-1.0-or-later"]
  head "https://github.com/perl5-dbi/DBD-mysql.git", branch: "master"

  bottle do
    sha256 cellar: :any,                 arm64_sequoia: "c31aa5bd0e31fd29f9aa99e8503693a855447d83c457ee0464503ca38e1deb08"
    sha256 cellar: :any,                 arm64_sonoma:  "9fc28598b8ba95a58dde2c80a0dd6e9111bebff625c78f7a65c38c0c21188cc6"
    sha256 cellar: :any,                 arm64_ventura: "8a154b2a01e8a5410294f02b520ed3c867294c50b5721b9ad0d12bc7fc26a909"
    sha256 cellar: :any,                 sonoma:        "55b14e52f3a4280819fa10ecb37da1fc0644d881f5053a7b923a5a16cd303838"
    sha256 cellar: :any,                 ventura:       "dce651e3ae7c073fe04af0ba79f388254a0d8967ef41a4376f9be99016366fb0"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "640c1908b0319455228d26ce96e9a03ab9d13303f8ababfabb6c05e230e986fd"
  end

  keg_only "it is mainly used internally by other formulae"

  depends_on "mysql" => :test
  depends_on "mysql-client"

  uses_from_macos "perl"

  resource "Devel::CheckLib" do
    url "https://cpan.metacpan.org/authors/id/M/MA/MATTN/Devel-CheckLib-1.16.tar.gz"
    sha256 "869d38c258e646dcef676609f0dd7ca90f085f56cf6fd7001b019a5d5b831fca"
  end

  resource "DBI" do
    on_linux do
      url "https://cpan.metacpan.org/authors/id/H/HM/HMBRAND/DBI-1.645.tgz"
      sha256 "e38b7a5efee129decda12383cf894963da971ffac303f54cc1b93e40e3cf9921"
    end
  end

  def install
    ENV.prepend_create_path "PERL5LIB", buildpath/"build_deps/lib/perl5"
    ENV.prepend_create_path "PERL5LIB", libexec/"lib/perl5"

    resources.each do |r|
      r.stage do
        install_base = (r.name == "Devel::CheckLib") ? buildpath/"build_deps" : libexec
        system "perl", "Makefile.PL", "INSTALL_BASE=#{install_base}", "INSTALLMAN1DIR=none", "INSTALLMAN3DIR=none"
        system "make", "install"
      end
    end

    system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}"

    make_args = []
    if OS.mac?
      # Reduce overlinking on macOS
      make_args << "OTHERLDFLAGS=-Wl,-dead_strip_dylibs"
      # Work around macOS DBI generating broken Makefile
      inreplace "Makefile" do |s|
        old_dbi_instarch_dir = s.get_make_var("DBI_INSTARCH_DIR")
        new_dbi_instarch_dir = "#{MacOS.sdk_path_if_needed}#{old_dbi_instarch_dir}"
        s.change_make_var! "DBI_INSTARCH_DIR", new_dbi_instarch_dir
        s.gsub! " #{old_dbi_instarch_dir}/Driver_xst.h", " #{new_dbi_instarch_dir}/Driver_xst.h"
      end
    end

    system "make", "install", *make_args
  end

  test do
    perl = OS.mac? ? "/usr/bin/perl" : Formula["perl"].bin/"perl"
    port = free_port
    socket = testpath/"mysql.sock"
    mysql = Formula["mysql"]
    mysqld_args = %W[
      --no-defaults
      --mysqlx=OFF
      --user=#{ENV["USER"]}
      --port=#{port}
      --socket=#{socket}
      --basedir=#{mysql.prefix}
      --datadir=#{testpath}/mysql
      --tmpdir=#{testpath}/tmp
    ]

    (testpath/"mysql").mkpath
    (testpath/"tmp").mkpath
    (testpath/"test.pl").write <<~PERL
      use strict;
      use warnings;
      use DBI;
      my $dbh = DBI->connect("DBI:mysql:;port=#{port};mysql_socket=#{socket}", "root", "", {'RaiseError' => 1});
      $dbh->do("CREATE DATABASE test");
      $dbh->do("CREATE TABLE test.foo (id INTEGER, name VARCHAR(20))");
      $dbh->do("INSERT INTO test.foo VALUES (1, " . $dbh->quote("Tim") . ")");
      $dbh->do("INSERT INTO test.foo VALUES (?, ?)", undef, 2, "Jochen");
      my $sth = $dbh->prepare("SELECT * FROM test.foo");
      $sth->execute();
      while (my $ref = $sth->fetchrow_hashref()) {
        print "$ref->{'id'},$ref->{'name'}\\n";
      }
      $sth->finish();
      $dbh->disconnect();
    PERL

    system mysql.bin/"mysqld", *mysqld_args, "--initialize-insecure"
    pid = spawn(mysql.bin/"mysqld", *mysqld_args)
    begin
      sleep 5
      ENV["PERL5LIB"] = libexec/"lib/perl5"
      assert_equal "1,Tim\n2,Jochen\n", shell_output("#{perl} test.pl")
    ensure
      system mysql.bin/"mysqladmin", "--port=#{port}", "--socket=#{socket}", "--user=root", "--password=", "shutdown"
      Process.kill "TERM", pid
    end
  end
end