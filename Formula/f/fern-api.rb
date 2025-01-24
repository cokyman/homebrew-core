class FernApi < Formula
  desc "Stripe-level SDKs and Docs for your API"
  homepage "https://buildwithfern.com/"
  url "https://registry.npmjs.org/fern-api/-/fern-api-0.51.3.tgz"
  sha256 "913e8bbce01998b9cdf0959aafacdb5ced75f7b9be92937bbaa93baa0f2cad6b"
  license "MIT"

  bottle do
    sha256 cellar: :any_skip_relocation, all: "f3b5ba0c80ec8d646436de88d16ad9f13821d6f27eb8fb51877f6c6ca96c3b9e"
  end

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    system bin/"fern", "init", "--docs", "--org", "brewtest"
    assert_path_exists testpath/"fern/docs.yml"
    assert_match "\"organization\": \"brewtest\"", (testpath/"fern/fern.config.json").read

    system bin/"fern", "--version"
  end
end
