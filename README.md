---
Title: Recipes
---

Food and recipes!

Recipes:

[Turkey Chili]({% link Turkey_Chili.md %})

[Bear's Brioche]({% link _recipes/BearsBrioche.md %})

{% for recipe in site.recipes %}
   [{% recipe.Title %}]({% recipe.url %})
{% endfor %}

