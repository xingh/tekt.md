module.exports = function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy("install.sh");
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
