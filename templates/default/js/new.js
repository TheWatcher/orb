

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


$(function() {
    $('#timemins').timeDurationPicker({
        lang: 'en_US',
        seconds: false,
        minutes: true,
        hours: true,
        days: true,
        months: false,
        years: false,
        onSelect: function(element, seconds, humanDuration) {
            $('#timemins').val(humanDuration);
            $('#timesecs').val(seconds);
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

    CKEDITOR.replace('method');
    CKEDITOR.replace('notes');

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
});
