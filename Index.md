---
Title: Indy's Recipes and related food stuff.
---

Food and recipes!

Recipes:

{% for recipe in site.recipes %}
   [{{ recipe.Title }}]({{ recipe.url }})
{% endfor %}

