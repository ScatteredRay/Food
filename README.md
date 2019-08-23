Food and recipes!

Recipes:

[Turkey Chili]({% link Turkey_Chili.md %})

[Bear's Brioche]({% link _recipes/BearsBrioche.md %})

{% for recipe in site.recipes %}
   <a href="{{ recipe.url | prepend: site.baseurl }}">
       <h2>{{ recipe.url }}</h2>
   </a>
{% endfor %}



