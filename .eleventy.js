module.exports = function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy("install.sh");
  eleventyConfig.addPassthroughCopy("install.ps1");
  eleventyConfig.addPassthroughCopy("tekt.catalog.yaml");
  eleventyConfig.addPassthroughCopy("tekt.body.png");
  eleventyConfig.addPassthroughCopy("tekt.cover.png");
  return {
    dir: {
      input: ".",
      includes: "_includes",
      output: "_site",
    },
    templateFormats: ["md", "njk", "html"],
    markdownTemplateEngine: "njk",
  };
};
