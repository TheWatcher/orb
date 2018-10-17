var CKCONFIG = {
    font_names: 'Arial/Arial, Helvetica, sans-serif;' +
        'Book Antiqua/Book Antiqua, serif;'+
        'Cambria/Cambria, serif;'+
	    'Courier New/Courier New, Courier, monospace;' +
	    'Georgia/Georgia, serif;' +
	    'Lucida Sans Unicode/Lucida Sans Unicode, Lucida Grande, sans-serif;' +
	    'Tahoma/Tahoma, Geneva, sans-serif;' +
	    'Times New Roman/Times New Roman, Times, serif;' +
	    'Trebuchet MS/Trebuchet MS, Helvetica, sans-serif;' +
	    'Verdana/Verdana, Geneva, sans-serif'
};

function check_name()
{
    var $name = $('#name').val();

}


function add_separator()
{
    var $new = $('#templates li.separator').clone(true);
    $new.hide().appendTo($('#ingredients')).fadeIn(300);
}


function add_ingredient(count)
{
    for(i = 0; i < count; ++i) {
        var $new = $('#templates li.ingred').clone(true);
        $new.hide().appendTo($('#ingredients')).fadeIn(300);

        $new.find(".ingredient").autocomplete({
            source: api.ingredients,
            minLength: 2
        });

    }
}


function build_ingdata()
{
    var values = new Array();

    // Go through all the children of the ingredient list
    // storing the value therein in elements of the values list
    $('#ingredients').children().each(function() {

        // Is this a separator row?
        if($(this).hasClass('separator')) {
            var name = $(this).find('input.separator').val();

            values.push({ "separator": true,
                          "name": name });
        } else {
            var quantity = $(this).find('input.quantity').val();
            var units    = $(this).find('select.units').val();
            var prep     = $(this).find('select.preps').val();
            var name     = $(this).find('input.ingredient').val();
            var notes    = $(this).find('input.notes').val();

            values.push({ "separator": false,
                          "quantity": quantity,
                          "units": units,
                          "prep": prep,
                          "name": name,
                          "notes": notes });

        }
    });

    $('#ingdata').val(JSON.stringify({ "ingredients": values }));
}


$(function() {
    $('#preptime').timeDurationPicker({
        lang: 'en_US',
        seconds: false,
        minutes: true,
        hours: true,
        days: true,
        months: false,
        years: false,
        onSelect: function(element, seconds, humanDuration) {
            $('#preptime').val(humanDuration);
            $('#prepsecs').val(seconds);
            console.log(seconds, humanDuration);
        }
    });
    $('#cooktime').timeDurationPicker({
        lang: 'en_US',
        seconds: false,
        minutes: true,
        hours: true,
        days: true,
        months: false,
        years: false,
        onSelect: function(element, seconds, humanDuration) {
            $('#cooktime').val(humanDuration);
            $('#cooksecs').val(seconds);
            console.log(seconds, humanDuration);
        }
    });

    $('#tags').select2({
        theme: "foundation",
        tags: true,
        tokenSeparators: [','],
        minimumInputLength: 2,
        multiple: true,
        ajax: {
            delay: 250,
            dataType: 'json',
            url: api.tags
        }
    });

    CKEDITOR.replace('method', CKCONFIG);
    CKEDITOR.replace('notes', CKCONFIG);

    $('#ingredients').sortable({
        placeholder: "ui-state-highlight"
    });

    $("#ingredients .ingredient").autocomplete({
        source: api.ingredients,
        minLength: 2
    });

    // Handle addition of separators and ingredients
    $('#addsep').on('click', function() { add_separator(); });
    $('.adding').on('click', function() { add_ingredient($(this).data('count')); });

    // Handle removal of separators and ingredients
    $('.deletectrl').on('click', function() {
        $(this).parents('li').fadeOut(300, function() { $(this).remove(); });
    });

    // Build the ingredient list before submitting
    $('#recipeform').on('submit', function() { build_ingdata(); return true });
});
