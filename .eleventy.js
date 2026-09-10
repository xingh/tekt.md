module.exports = function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy("install.sh");
  eleventyConfig.addPassthroughCopy("install.ps1");
  eleventyConfig.addPassthroughCopy("tekt.catalog.yaml");
  eleventyConfig.addPassthroughCopy("tekt.body.png");
  eleventyConfig.addPassthroughCopy("tekt.cover.png");

  // Resolve the arkitype layer (00–04) whose page lives at `url`.
  eleventyConfig.addFilter("layerFor", (layers, url) =>
    (layers || []).find((l) => l.url === url) || null
  );

  // Neighbor along the 00 → 04 build order; the home page sits before 00.
  eleventyConfig.addFilter("layerAt", (layers, url, offset) => {
    const i = (layers || []).findIndex((l) => l.url === url);
    if (i === -1 && url !== "/") return null;
    return layers[i + offset] || null;
  });

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
