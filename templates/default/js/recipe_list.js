$(function() {
    var options = {
        valueNames: [ 'ljs-name', 'ljs-type', 'ljs-status', 'ljs-time', 'tags' ],
        plugins: [ ListFuzzySearch() ]
    };

    var recipeList = new List('recipelist', options);

    $('#listfilter').delaysearch(recipeList);
    $('#listfilter').clearable();

});